variable "tag_keys" {
  description = "User-defined tag keys to activate as AWS Cost Allocation Tags in Billing/Cost Explorer. Each key must already be applied to at least one resource in the account before AWS will let it be activated — see this module's README."
  type        = list(string)
  default     = ["Project", "Environment", "Tier", "CostCenter"]
}

variable "eks_split_cost_allocation_tag_keys" {
  description = "AWS-generated `aws:eks:*` tag keys (Split Cost Allocation Data for EKS) to activate the same way as tag_keys — see this module's README for why these were assumed to be console-only and turned out not to be. Pass an empty list to skip these if the account has no EKS clusters."
  type        = list(string)
  default     = ["aws:eks:cluster-name", "aws:eks:namespace", "aws:eks:workload-name", "aws:eks:workload-type", "aws:eks:deployment", "aws:eks:node"]
}
