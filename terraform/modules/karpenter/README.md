# karpenter

IAM (controller IRSA role + node role), the Spot-interruption SQS queue and EventBridge rules, and the Karpenter Helm release itself. `NodePool`/`EC2NodeClass` custom resources are deliberately **not** managed here — they're plain Kubernetes manifests applied via `kubectl`, in [`kubernetes/eks/karpenter/`](../../../kubernetes/eks/karpenter/), matching the GitOps-friendly split of "Terraform owns cloud infra + controller install, kubectl/ArgoCD owns cluster-native resources."

Versioned via git tags (`modules/karpenter/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

Depends on outputs from [`eks-cluster`](../eks-cluster/) (`oidc_provider_arn`, `oidc_provider_url`, `cluster_endpoint`) and calls [`iam-irsa`](../iam-irsa/) internally for the controller role.

## Why the controller runs on the core node group, not Karpenter-managed capacity

Karpenter can't provision the node it needs to run on before it's running — see `core_node_selector` and the `eks-cluster` module's core system node group.

## Example

```hcl
module "karpenter" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/karpenter?ref=modules/karpenter/v1.0.1"

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
