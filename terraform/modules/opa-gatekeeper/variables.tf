variable "namespace" {
  description = "Namespace Gatekeeper runs in."
  type        = string
  default     = "gatekeeper-system"
}

variable "gatekeeper_helm_version" {
  description = <<-EOT
    Version of the Gatekeeper Helm chart. Must match
    ansible/roles/opa-gatekeeper's gatekeeper_helm_version default — the
    whole point of this module existing alongside that role is that both
    K8s tiers run the identical controller version and config; see
    docs/architecture.md.
  EOT
  type        = string
  default     = "3.17.1"
}

variable "audit_interval_seconds" {
  description = "How often Gatekeeper re-audits existing resources against constraints (not just new admissions)."
  type        = number
  default     = 60
}

variable "replicas" {
  description = "Controller-manager replica count."
  type        = number
  default     = 2
}
