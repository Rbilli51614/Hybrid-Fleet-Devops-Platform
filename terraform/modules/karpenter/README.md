# karpenter

IAM (controller IRSA role + node role), the Spot-interruption SQS queue and EventBridge rules, and the Karpenter Helm release itself. `NodePool`/`EC2NodeClass` custom resources are deliberately **not** managed here — they're plain Kubernetes manifests applied via `kubectl`, in [`kubernetes/eks/karpenter/`](../../../kubernetes/eks/karpenter/), matching the GitOps-friendly split of "Terraform owns cloud infra + controller install, kubectl/ArgoCD owns cluster-native resources."

Versioned via git tags (`modules/karpenter/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

Depends on outputs from [`eks-cluster`](../eks-cluster/) (`oidc_provider_arn`, `oidc_provider_url`, `cluster_endpoint`) and calls [`iam-irsa`](../iam-irsa/) internally for the controller role.

## Why the controller runs on the core node group, not Karpenter-managed capacity

Karpenter can't provision the node it needs to run on before it's running — see `core_node_selector` and the `eks-cluster` module's core system node group.

## `ec2:CreateTags` scoped to `instance/*` alone isn't enough to launch a node

A real scale-out test — an oversized pod forcing Karpenter to provision new capacity — failed at the very first step, before `RunInstances` was ever called:

```
UnauthorizedOperation: ... not authorized to perform: ec2:CreateTags on
resource: arn:...:launch-template/* because no identity-based policy
allows the ec2:CreateTags action
```

The original policy granted `ec2:CreateTags` only on `instance/*`, folded into the same statement as `ec2:TerminateInstances`. But launching a node means Karpenter creates and tags *several* resource types along the way — the launch template itself, the instance, its root volume, its ENI, and (for Spot) the spot instance request — not just the instance. Fixed with a dedicated `AllowScopedResourceCreationTagging` statement covering all five resource types, scoped down via `aws:RequestTag/kubernetes.io/cluster/<name>: owned` and `ec2:CreateAction` conditions to Karpenter's own creation calls (`RunInstances`/`CreateFleet`/`CreateLaunchTemplate`), matching AWS's own reference Karpenter controller policy rather than the ad-hoc `instance/*`-only grant this started with.

This was actually discovered as two separate gaps, one layer apart: fixing `launch-template/*` (v1.0.2) let the launch template get created, which then surfaced the *next* missing resource type — `UnauthorizedOperation` on `ec2:CreateTags` against `arn:...:fleet/*`, since Karpenter places instances via `CreateFleet`, not a bare `RunInstances` call. `fleet/*` was added to the same statement (v1.0.3).

## First-ever Spot launch in the account needs one more permission: creating its service-linked role

Getting past both `CreateTags` gaps surfaced a third, different-shaped failure once Karpenter actually picked Spot capacity for the launch (the default `NodePool` allows both `spot` and `on-demand` — see [`kubernetes/eks/karpenter/nodepool-default.yaml`](../../../kubernetes/eks/karpenter/nodepool-default.yaml)):

```
AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided
credentials do not have permission to create the service-linked role
for EC2 Spot Instances.
```

This AWS account had never used EC2 Spot before, so EC2 tried to auto-create `AWSServiceRoleForEC2Spot` on Karpenter's behalf, and the controller role had no `iam:CreateServiceLinkedRole` permission at all. Fixed (v1.0.4) with a statement scoped via `iam:AWSServiceName: spot.amazonaws.com` so it can only ever create that one service-linked role — matches AWS's own reference Karpenter controller policy.

Fixing all three IAM gaps got a real instance all the way to `Launched=True` — but it still never showed up in `kubectl get nodes`. See the next two sections for what was actually going on (a cluster-access gap, not an IAM-policy-on-the-controller gap), found via SSM directly on the instance since nothing about it ever reached the Kubernetes side to log from.

While fixing the tagging gaps, the controller's own launch-template garbage collector (cleaning up templates orphaned by the several failed launches above) hit the same class of problem: `UnauthorizedOperation` on `ec2:DeleteLaunchTemplate`. Folded into a resource-tag-scoped `AllowScopedDeletion` statement (v1.0.5) alongside `ec2:TerminateInstances`, matching AWS's reference policy, rather than the unconditioned `instance/*`-only termination grant this started with.

## A launched, running, kubelet-running instance that never joins the cluster: `authentication_mode = "API"` doesn't auto-register self-managed nodes

Even after all the IAM gaps above were fixed, the launched instance never appeared in `kubectl get nodes` — and Karpenter's own controller logs went quiet after logging `"launched nodeclaim"`, since as far as Karpenter's concerned the instance exists; it has no visibility into whether kubelet ever successfully registers. Found by going straight to the instance itself via SSM Session Manager (`aws ssm send-command` running `systemctl status kubelet`, since the [`vm-k8s-asg`](../vm-k8s-asg/) node role already has `AmazonSSMManagedInstanceCore` — no SSH needed here either):

```
kubelet[...]: "Attempting to register node" node="ip-10-0-0-181.ec2.internal"
kubelet[...]: E... "Failed to ensure lease exists, will retry" err="Unauthorized"
kubelet[...]: E... "Unable to register node with API server" err="Unauthorized" node="..."
```

Root cause: [`eks-cluster`](../eks-cluster/)'s cluster runs pure `authentication_mode = "API"` (no `aws-auth` ConfigMap fallback), and only grants access entries to `var.admin_principal_arns` — nothing registers a *node* IAM role at all. An EKS-*managed* node group (the core system nodes) gets that registration automatically as part of being a managed node group; Karpenter's nodes are self-managed (EC2 instances Karpenter launches directly), so nothing did it for them. Fixed (v1.0.5) by adding an `aws_eks_access_entry` of `type = "EC2_LINUX"` for the Karpenter node role — that type gets standard node-bootstrap permissions automatically, with no `aws_eks_access_policy_association` needed (unlike the admin entries, which need `AmazonEKSClusterAdminPolicy` explicitly associated).

Verified for real, end to end, across all five fixes: an oversized test pod forced Karpenter to provision a Spot `r7a.medium`, its NodeClaim's `status.conditions` reached `Launched=True` / `Registered=True` / `Initialized=True` / `Ready=True`, the instance joined the cluster as a `Ready` node, and the pod scheduled onto it and ran (`1/1 Running`).

## Example

```hcl
module "karpenter" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/karpenter?ref=modules/karpenter/v1.0.5"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name | `string` | — |
| `cluster_endpoint` | EKS API server endpoint | `string` | — |
| `oidc_provider_arn` / `oidc_provider_url` | Cluster IRSA trust anchor | `string` | — |
| `node_iam_additional_policy_arns` | Extra policies for Karpenter-launched nodes | `list(string)` | `[]` |
| `karpenter_version` | Karpenter Helm chart version | `string` | `"1.0.6"` |
| `karpenter_namespace` | Namespace for the controller | `string` | `"kube-system"` |
| `core_node_selector` | Node selector pinning the controller to the core node group | `map(string)` | `{role = "system-core"}` |
| `tags` | Extra tags on IAM/SQS/EventBridge resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `node_iam_role_name` | Set as `spec.role` in EC2NodeClass manifests |
| `node_iam_role_arn` | Node role ARN |
| `controller_role_arn` | Controller's IRSA role ARN |
| `interruption_queue_name` | SQS queue name for Spot interruption handling |
