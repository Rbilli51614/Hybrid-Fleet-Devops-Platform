output "controller_role_arn" {
  description = "IRSA role ARN used by the controller."
  value       = module.controller_irsa.role_arn
}

output "iam_policy_arn" {
  description = "ARN of the fetched-at-apply-time upstream IAM policy."
  value       = aws_iam_policy.controller.arn
}
