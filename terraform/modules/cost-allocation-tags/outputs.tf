output "activated_tag_keys" {
  description = "Tag keys activated for cost allocation."
  value       = [for t in aws_ce_cost_allocation_tag.this : t.tag_key]
}
