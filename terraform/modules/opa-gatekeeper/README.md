# opa-gatekeeper

Installs the Gatekeeper Helm chart on the EKS cluster — the cloud-tier half of this repo's policy parity story. The VM-tier half is [`ansible/roles/opa-gatekeeper`](../../../ansible/roles/opa-gatekeeper/), installing the *identical* chart version and values via `kubernetes.core.helm` instead of Terraform, since that tier has no Terraform-managed Kubernetes layer at all. Only the controller is installed here or there — the actual policy content (`ConstraintTemplate`s, `Constraint`s) is kubectl-applied identically to both clusters from [`kubernetes/base/opa-gatekeeper/`](../../../kubernetes/base/opa-gatekeeper/) and [`policy/gatekeeper-constraints/`](../../../policy/gatekeeper-constraints/) — see [`docs/architecture.md`](../../../docs/architecture.md) for why that split, and why "identically on both clusters" is a literal claim here, not just a diagram label.

Versioned via git tags (`modules/opa-gatekeeper/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

The only module in this repo with zero AWS resources — Gatekeeper is a pure in-cluster admission webhook.

## Example

```hcl
module "gatekeeper" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/opa-gatekeeper?ref=modules/opa-gatekeeper/v1.0.0"
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `namespace` | Namespace Gatekeeper runs in | `string` | `"gatekeeper-system"` |
| `gatekeeper_helm_version` | Chart version — must match the Ansible role's default for the two tiers to actually run identical policy enforcement | `string` | `"3.17.1"` |
| `audit_interval_seconds` | How often existing (not just newly-admitted) resources are re-audited | `number` | `60` |
| `replicas` | Controller-manager replica count | `number` | `2` |

| Output | Description |
|---|---|
| `namespace` | For kubectl-applying constraint templates/constraints against |
| `helm_version` | Cross-check against the Ansible role's version |
