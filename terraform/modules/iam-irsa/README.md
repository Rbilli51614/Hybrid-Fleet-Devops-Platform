# iam-irsa

Generic IAM Roles for Service Accounts (IRSA) module: builds the OIDC-federated trust policy scoping an IAM role to one Kubernetes service account, and attaches managed and/or inline policies. Used by the [`karpenter`](../karpenter/) module for the controller's role, and intended for reuse by any future in-cluster workload that needs AWS permissions (ARC runners, OTel Collector, etc.) instead of long-lived static credentials.

Versioned via git tags (`modules/iam-irsa/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Example

```hcl
module "karpenter_irsa" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/iam-irsa?ref=modules/iam-irsa/v1.0.0"

  role_name             = "karpenter-controller"
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  namespace             = "kube-system"
  service_account_name  = "karpenter"
  inline_policy_json    = data.aws_iam_policy_document.karpenter_controller.json
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `role_name` | Name for the IAM role | `string` | — |
| `oidc_provider_arn` | Cluster OIDC provider ARN | `string` | — |
| `oidc_provider_url` | Cluster OIDC issuer URL (no `https://`) | `string` | — |
| `namespace` | Service account's namespace | `string` | — |
| `service_account_name` | Service account name | `string` | — |
| `policy_arns` | Managed policy ARNs to attach | `list(string)` | `[]` |
| `inline_policy_json` | Inline policy document (JSON) | `string` | `null` |
| `tags` | Extra tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `role_arn` | Set as the `eks.amazonaws.com/role-arn` annotation on the matching service account |
| `role_name` | IAM role name |
