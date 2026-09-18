output "github_app_secret_arn" {
  description = "ARN of the Secrets Manager secret holding GitHub App credentials. Populate its real value out of band, then sync it into a Kubernetes secret — see README."
  value       = aws_secretsmanager_secret.github_app.arn
}

output "github_app_secret_name" {
  description = "Name of the Secrets Manager secret holding GitHub App credentials."
  value       = aws_secretsmanager_secret.github_app.name
}

output "runner_irsa_role_arn" {
  description = "ARN of the runner pods' IRSA role, if runner_irsa_policy_json was set."
  value       = try(module.runner_irsa[0].role_arn, null)
}

output "controller_namespace" {
  description = "Namespace the ARC controller runs in."
  value       = var.controller_namespace
}

output "runners_namespace" {
  description = "Namespace runner scale sets should be installed into."
  value       = var.runners_namespace
}
