# Activates each key as an AWS Cost Allocation Tag, so it shows up as a
# groupable/filterable column in Cost Explorer and the Cost and Usage
# Report instead of sitting inert on every resource. This is an
# account-level Billing setting, not a per-resource one — hence its own
# small module and its own "global" stack, applied last (see README).
#
# One resource, two tag flavors: user-defined tag_keys (Project/Environment/
# etc., applied by this repo's own Terraform) and the AWS-generated
# `aws:eks:*` ones (Split Cost Allocation Data for EKS). Both go through the
# exact same aws_ce_cost_allocation_tag resource and the same
# ce:UpdateCostAllocationTagsStatus API call underneath it — see the README
# for why the `aws:eks:*` ones were originally assumed to need a manual
# Billing-console click and turned out not to.
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = toset(concat(var.tag_keys, var.eks_split_cost_allocation_tag_keys))

  tag_key = each.value
  status  = "Active"
}
