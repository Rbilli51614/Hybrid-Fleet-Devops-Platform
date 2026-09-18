# cost-allocation-tags

Activates a set of tag keys as AWS Cost Allocation Tags via `aws_ce_cost_allocation_tag`, so `Project`, `Environment`, `Tier`, and `CostCenter` — already applied to every resource in this repo (`Project`/`Environment` from `terraform/root.hcl`'s `default_tags`, `Tier`/`CostCenter` from each stack's own `inputs.tags`) — actually show up as groupable/filterable columns in Cost Explorer and the CUR, instead of sitting inert on every resource. See [`docs/architecture.md`](../../../docs/architecture.md#cost-allocation-tags-the-aws-side-and-the-k8s-side) for how this fits the Cost layer's per-team chargeback story end to end.

Versioned via git tags (`modules/cost-allocation-tags/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Why `CostCenter` is `"platform-engineering"` everywhere, not per-tier

Every stack this repo builds — VPCs, both K8s tiers' controllers, Nexus, the VPN, observability — is genuinely owned and paid for by one team: the platform team running this fleet. Tagging `Tier = "cloud"` vs `"onprem"` (already in place since Phase 0) answers "which environment," not "which team pays" — there's only one team here to pay for any of it, so a fabricated per-tier `CostCenter` split would be decorative, not honest.

Real per-*tenant*-team chargeback belongs one layer down, at the workload layer, once other teams' workloads actually run on these shared clusters — which is exactly what [`policy/gatekeeper-constraints/require-team-label.yaml`](../../../policy/gatekeeper-constraints/) already enforces (every `Deployment`, on both clusters, must carry a `team` label). AWS bridges that K8s-level label into the same Cost Explorer/CUR view this module activates via **Split Cost Allocation Data for Amazon EKS with Kubernetes labels** — pod-level labels imported as CUR columns, up to 50 per pod. That bridge is an account-level Billing console toggle (Cost Allocation Tags → Kubernetes labels → Activate), not a resource this or any Terraform provider currently exposes — same "documented manual step" pattern as `terraform/modules/observability`'s Grafana data source (see that module's README).

## The activation delay — apply this stack last

AWS only lets a tag be activated for cost allocation **after it's already been applied to at least one resource for roughly 24 hours**. Applying this stack immediately after first standing up the fleet will fail (or silently activate nothing, depending on provider version) for any tag key that's brand new. In practice: stand up the rest of the fleet first, wait a day, then apply `terraform/live/global/cost-allocation-tags` — which is also why this lives under `live/global/` rather than `live/dev/`, alongside `state-backend`: cost allocation tag activation is an account-wide Billing setting, not a per-environment resource.

## Example

```hcl
module "cost_allocation_tags" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/cost-allocation-tags?ref=modules/cost-allocation-tags/v1.0.0"
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `tag_keys` | Tag keys to activate for cost allocation | `list(string)` | `["Project", "Environment", "Tier", "CostCenter"]` |

| Output | Description |
|---|---|
| `activated_tag_keys` | The tag keys this apply activated |

## Not yet built

Split Cost Allocation Data for Amazon EKS (the Kubernetes-label-to-CUR bridge described above) isn't Terraform-managed — it's an account-level Billing console step with no corresponding resource in the `aws` provider as of this writing. A documented manual step until AWS ships one, same as this repo's other "Terraform's job stops here, a console click finishes it" boundaries.
