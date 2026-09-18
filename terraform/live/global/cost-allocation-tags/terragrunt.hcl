# Account-level Billing setting (Cost Allocation Tag activation), not a
# per-environment resource — lives alongside state-backend under global/
# rather than under dev/. Unlike state-backend, this stack has no
# bootstrap chicken-and-egg problem (it doesn't create the remote state
# backend it runs against), so it's Terragrunt-managed like every other
# stack instead of plain terraform.
#
# Apply this one LAST, and not until the rest of the fleet's tags
# (Project/Environment/Tier/CostCenter) have existed on at least one
# resource for ~24h — see terraform/modules/cost-allocation-tags/README.md.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/cost-allocation-tags?ref=modules/cost-allocation-tags/v1.0.0"
}

inputs = {}
