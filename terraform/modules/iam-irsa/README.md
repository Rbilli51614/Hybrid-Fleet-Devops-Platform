# iam-irsa

Generic IAM Roles for Service Accounts (IRSA) module: builds the OIDC-federated trust policy scoping an IAM role to one Kubernetes service account, and attaches managed and/or inline policies. Used by the [`karpenter`](../karpenter/) module for the controller's role, and intended for reuse by any future in-cluster workload that needs AWS permissions (ARC runners, OTel Collector, etc.) instead of long-lived static credentials.

Versioned via git tags (`modules/iam-irsa/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Why `attach_inline_policy` is a separate variable from `inline_policy_json`

The obvious design is `count = var.inline_policy_json != null ? 1 : 0` — and that's what this module shipped with until a real apply broke it. Karpenter's controller policy (`data.aws_iam_policy_document.controller` in the `karpenter` module) scopes an `iam:PassRole` statement to `aws_iam_role.node.arn`, a sibling resource created in the *same* apply. That makes the whole computed `.json` value — not just its content, but whether Terraform considers it "known" at all — unresolvable at plan time, which cascades into `count` itself being unknown: `Error: Invalid count argument ... cannot be determined until apply`. `terraform validate` and a mocked `terragrunt plan` both miss this entirely, since it's about two resources *within the same apply* referencing each other, not a cross-stack dependency mocks can stand in for — this one only ever showed up on a real apply against real, not-yet-existing infrastructure.

The fix: `attach_inline_policy` is a plain `bool` the caller sets directly (always a literal at the call site, never derived from a data source), decoupled entirely from whatever `inline_policy_json`'s value turns out to be. `count` depends only on that literal, so it's always resolvable at plan time regardless of what the policy document itself references.

## Example

```hcl
module "karpenter_irsa" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/iam-irsa?ref=modules/iam-irsa/v1.0.1"

  role_name             = "karpenter-controller"
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  namespace             = "kube-system"
  service_account_name  = "karpenter"
  attach_inline_policy  = true
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
| `attach_inline_policy` | Whether to create the inline policy — see above for why this isn't just inferred from `inline_policy_json != null` | `bool` | `false` |
| `inline_policy_json` | Inline policy document (JSON), may be a value only known after apply | `string` | `null` |
| `tags` | Extra tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `role_arn` | Set as the `eks.amazonaws.com/role-arn` annotation on the matching service account |
| `role_name` | IAM role name |
