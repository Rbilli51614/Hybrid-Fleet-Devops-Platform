variable "cluster_name" {
  description = "Name of the EKS cluster ARC is installed into."
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

variable "controller_namespace" {
  description = "Namespace the ARC controller itself runs in."
  type        = string
  default     = "arc-systems"
}

variable "runners_namespace" {
  description = "Namespace runner scale sets and their ephemeral runner pods run in. Kept separate from controller_namespace so a NetworkPolicy can scope what runner pods can reach without also touching the controller (see docs/pitfalls.md on ephemeral runners as a lateral-movement surface)."
  type        = string
  default     = "arc-runners"
}

variable "controller_helm_version" {
  description = "Version of the gha-runner-scale-set-controller Helm chart."
  type        = string
  default     = "0.9.3"
}

variable "github_app_secret_name" {
  description = "Name of the AWS Secrets Manager secret that holds the GitHub App credentials (app ID, installation ID, private key) used to register runners. Terraform only creates the secret container with placeholder content — populate the real values out of band (see module README) and they're never stored in state."
  type        = string
  default     = null
}

variable "runner_irsa_policy_json" {
  description = "Inline IAM policy (JSON) granting the runner pods' service account AWS access for CI jobs (e.g. ECR push, S3 artifact access). Left minimal by default; scope per team before granting anything broader. Set to null to skip creating the runner IRSA role entirely."
  type        = string
  default     = null
}

variable "runner_service_account_name" {
  description = "Kubernetes service account name (in runners_namespace) that runner pods use, and that the runner IRSA role trusts. Must match `template.spec.serviceAccountName` in the gha-runner-scale-set Helm values."
  type        = string
  default     = "arc-runner"
}

variable "tags" {
  description = "Additional tags applied to IAM/Secrets Manager resources."
  type        = map(string)
  default     = {}
}
