# cost-allocation-tags

Activates a set of tag keys as AWS Cost Allocation Tags via `aws_ce_cost_allocation_tag`, so `Project`, `Environment`, `Tier`, and `CostCenter` — already applied to every resource in this repo (`Project`/`Environment` from `terraform/root.hcl`'s `default_tags`, `Tier`/`CostCenter` from each stack's own `inputs.tags`) — actually show up as groupable/filterable columns in Cost Explorer and the CUR, instead of sitting inert on every resource. The same mechanism also activates the six AWS-generated `aws:eks:*` Split Cost Allocation Data tags (Kubernetes namespace/node/workload — see below). See [`docs/architecture.md`](../../../docs/architecture.md#cost-allocation-tags-the-aws-side-and-the-k8s-side) for how this fits the Cost layer's per-team chargeback story end to end.

Versioned via git tags (`modules/cost-allocation-tags/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Why `CostCenter` is `"platform-engineering"` everywhere, not per-tier

Every stack this repo builds — VPCs, both K8s tiers' controllers, Nexus, the VPN, observability — is genuinely owned and paid for by one team: the platform team running this fleet. Tagging `Tier = "cloud"` vs `"onprem"` (already in place since Phase 0) answers "which environment," not "which team pays" — there's only one team here to pay for any of it, so a fabricated per-tier `CostCenter` split would be decorative, not honest.

Real per-*tenant*-team chargeback belongs one layer down, at the workload layer, once other teams' workloads actually run on these shared clusters — which is exactly what [`policy/gatekeeper-constraints/require-team-label.yaml`](../../../policy/gatekeeper-constraints/) already enforces (every `Deployment`, on both clusters, must carry a `team` label). AWS bridges that K8s-level label into the same Cost Explorer/CUR view via **Split Cost Allocation Data for Amazon EKS** — see the next section for how that bridge actually gets turned on.

## The Kubernetes-label bridge turned out not to be console-only after all

This module originally documented Split Cost Allocation Data for EKS as an account-level Billing *console* toggle with no Terraform-manageable resource — that assumption was wrong, found by actually checking a live account rather than trusting the docs. `aws ce list-cost-allocation-tags --type AWSGenerated` lists `aws:eks:cluster-name`, `aws:eks:namespace`, `aws:eks:workload-name`, `aws:eks:workload-type`, `aws:eks:deployment`, and `aws:eks:node` as ordinary cost allocation tags — `Type: AWSGenerated` instead of `UserDefined`, but activated through the exact same `ce:UpdateCostAllocationTagsStatus` API (confirmed for real: `aws ce update-cost-allocation-tags-status --cost-allocation-tags-status TagKey="aws:eks:cluster-name",Status="Active"` returned `{"Errors": []}` and the tag showed `Status: Active` moments later). `aws_ce_cost_allocation_tag`'s schema never restricted this to `UserDefined` tags in the first place — the module just never tried.

Five of the six activate automatically once EKS starts emitting workloads (this account had them `Active` with no `list-cost-allocation-tag-backfill-history` entry at all — AWS turns them on itself once it sees the underlying usage data); `aws:eks:cluster-name` was the one holdout, and one API call fixed it. This module now activates all six through `eks_split_cost_allocation_tag_keys` alongside the user-defined ones, so a future account starts from an explicit, applied state instead of hoping AWS's auto-activation kicks in.

**What's still genuinely manual**: activating these tags makes the columns exist in Cost Explorer/the CUR — it doesn't retroactively populate historical data, and per-pod label granularity beyond the six standard dimensions above (up to 50 labels per pod, per AWS's docs) still needs the values to actually appear in usage data before they're groupable. Nothing left here needs a console click, though.

## The activation delay — apply this stack last

AWS only lets a tag be activated for cost allocation **after it's already been applied to at least one resource for roughly 24 hours**. Applying this stack immediately after first standing up the fleet will fail (or silently activate nothing, depending on provider version) for any tag key that's brand new. In practice: stand up the rest of the fleet first, wait a day, then apply `terraform/live/global/cost-allocation-tags` — which is also why this lives under `live/global/` rather than `live/dev/`, alongside `state-backend`: cost allocation tag activation is an account-wide Billing setting, not a per-environment resource.

## Example

```hcl
module "cost_allocation_tags" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/cost-allocation-tags?ref=modules/cost-allocation-tags/v1.0.1"
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `tag_keys` | User-defined tag keys to activate for cost allocation | `list(string)` | `["Project", "Environment", "Tier", "CostCenter"]` |
| `eks_split_cost_allocation_tag_keys` | AWS-generated `aws:eks:*` tag keys to activate the same way — pass `[]` if the account has no EKS clusters | `list(string)` | `["aws:eks:cluster-name", "aws:eks:namespace", "aws:eks:workload-name", "aws:eks:workload-type", "aws:eks:deployment", "aws:eks:node"]` |

| Output | Description |
|---|---|
| `activated_tag_keys` | The tag keys this apply activated (both flavors combined) |
