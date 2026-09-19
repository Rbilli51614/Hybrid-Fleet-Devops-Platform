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

## Example

```hcl
module "karpenter" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/karpenter?ref=modules/karpenter/v1.0.4"

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
