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
  description = "Optional inline IAM policy document (JSON) to attach to the role, for permissions not available as a managed policy. May be a value only known after apply (e.g. a policy document referencing a sibling resource's ARN created in the same apply) — see attach_inline_policy for why whether to create the resource is a separate variable from this one."
  type        = string
  default     = null
}

variable "attach_inline_policy" {
  description = "Whether to create the inline policy from inline_policy_json. Deliberately separate from checking inline_policy_json != null: when that value is computed from a policy document that references another resource created in the same apply (e.g. aws_iam_role.node.arn), the *entire* computed JSON string — including its nullness — is unknown at plan time, and count can't be derived from an unknown value (\"Invalid count argument ... cannot be determined until apply\"). This flag is always a literal true/false at the call site, so it's always known."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to the role."
  type        = map(string)
  default     = {}
}
