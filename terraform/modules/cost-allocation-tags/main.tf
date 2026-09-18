# Activates each key as a user-defined AWS Cost Allocation Tag, so it shows
# up as a groupable/filterable column in Cost Explorer and the Cost and
# Usage Report instead of sitting inert on every resource. This is an
# account-level Billing setting, not a per-resource one — hence its own
# small module and its own "global" stack, applied last (see README).
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = toset(var.tag_keys)

  tag_key = each.value
  status  = "Active"
}
