variable "tag_keys" {
  description = "Tag keys to activate as AWS Cost Allocation Tags in Billing/Cost Explorer. Each key must already be applied to at least one resource in the account before AWS will let it be activated — see this module's README."
  type        = list(string)
  default     = ["Project", "Environment", "Tier", "CostCenter"]
}
