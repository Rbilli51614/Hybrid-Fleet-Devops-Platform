output "namespace" {
  description = "Namespace Gatekeeper runs in, for kubectl-applying constraint templates/constraints against."
  value       = var.namespace
}

output "helm_version" {
  description = "Installed Gatekeeper Helm chart version — cross-check against ansible/roles/opa-gatekeeper's version for the VM tier."
  value       = var.gatekeeper_helm_version
}
