output "controller_role_arn" {
  description = "IRSA role ARN used by the collector."
  value       = module.controller_irsa.role_arn
}

output "namespace" {
  description = "Namespace the collector runs in."
  value       = var.namespace
}
