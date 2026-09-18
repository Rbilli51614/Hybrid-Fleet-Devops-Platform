variable "role_name" {
  description = "Name for the IAM role."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (from the eks-cluster module's `oidc_provider_arn` output)."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix (from the eks-cluster module's `oidc_provider_url` output)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account this role is scoped to."
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name this role is scoped to."
  type        = string
}

variable "policy_arns" {
  description = "List of existing IAM policy ARNs to attach to the role."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional inline IAM policy document (JSON) to attach to the role, for permissions not available as a managed policy."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to the role."
  type        = map(string)
  default     = {}
}
