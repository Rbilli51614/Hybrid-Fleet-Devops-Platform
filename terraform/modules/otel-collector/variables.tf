variable "cluster_name" {
  description = "Name of the EKS cluster the collector runs on."
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

variable "amp_workspace_arn" {
  description = "Amazon Managed Prometheus workspace ARN (from terraform/modules/observability's amp_workspace_arn output) — scopes the collector's remote_write IAM permission to exactly this workspace."
  type        = string
}

variable "amp_remote_write_url" {
  description = "AMP remote_write endpoint (from terraform/modules/observability's amp_remote_write_url output). Rendered into the shared kubernetes/base/otel-collector/values.yaml.tmpl."
  type        = string
}

variable "aws_region" {
  description = "Region the AMP workspace lives in. Rendered into the shared values template for the sigv4auth extension."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace the collector runs in."
  type        = string
  default     = "otel-collector-system"
}

variable "otel_collector_helm_version" {
  description = <<-EOT
    Version of the opentelemetry-collector Helm chart. Must match
    ansible/roles/otel-collector's default — both tiers should run the
    same collector version against the shared pipeline config, same
    reasoning as terraform/modules/opa-gatekeeper and its Ansible
    counterpart.
  EOT
  type        = string
  default     = "0.108.0"
}

variable "tags" {
  description = "Additional tags applied to the IRSA role."
  type        = map(string)
  default     = {}
}
