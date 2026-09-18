output "role_arn" {
  description = "ARN of the created IRSA role. Set as the eks.amazonaws.com/role-arn annotation on the matching Kubernetes service account."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the created IRSA role."
  value       = aws_iam_role.this.name
}
