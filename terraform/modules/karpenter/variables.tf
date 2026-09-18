variable "cluster_name" {
  description = "Name of the EKS cluster Karpenter manages capacity for."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint (from the eks-cluster module's `cluster_endpoint` output). Passed to the Karpenter controller so it can reach the API server."
  type        = string
}

variable "oidc_provider_arn" {
  description = "Cluster IAM OIDC provider ARN (from the eks-cluster module's `oidc_provider_arn` output)."
  type        = string
}

variable "oidc_provider_url" {
  description = "Cluster OIDC issuer URL without https:// (from the eks-cluster module's `oidc_provider_url` output)."
  type        = string
}

variable "node_iam_additional_policy_arns" {
  description = "Extra managed policy ARNs to attach to the IAM role Karpenter assigns to the nodes it launches, beyond the standard EKS worker policies."
  type        = list(string)
  default     = []
}

variable "karpenter_version" {
  description = "Version of the Karpenter Helm chart to install."
  type        = string
  default     = "1.0.6"
}

variable "karpenter_namespace" {
  description = "Namespace to install the Karpenter controller into. Should schedule onto the core system node group, not nodes Karpenter itself manages."
  type        = string
  default     = "kube-system"
}

variable "core_node_selector" {
  description = "Node selector forcing the Karpenter controller pods onto the pre-existing core system node group (see eks-cluster module), so Karpenter doesn't depend on capacity only it can create."
  type        = map(string)
  default = {
    "role" = "system-core"
  }
}

variable "tags" {
  description = "Additional tags applied to IAM/SQS/EventBridge resources."
  type        = map(string)
  default     = {}
}
