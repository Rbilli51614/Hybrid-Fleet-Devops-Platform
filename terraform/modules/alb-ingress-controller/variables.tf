variable "cluster_name" {
  description = "Name of the EKS cluster the controller manages ALBs/NLBs for."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster (and the ALBs/NLBs the controller creates) live in."
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

variable "aws_region" {
  description = "AWS region the cluster runs in."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace the controller runs in."
  type        = string
  default     = "kube-system"
}

variable "controller_helm_version" {
  description = "Version of the aws-load-balancer-controller Helm chart."
  type        = string
  default     = "1.8.1"
}

variable "controller_app_version" {
  description = <<-EOT
    Git tag of the aws-load-balancer-controller release whose published IAM
    policy is fetched at apply time (see main.tf) — must be the app version
    that controller_helm_version actually ships, not an independent pin.
    Chart 1.8.1 ships controller app v2.8.1; check
    https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases
    if you bump controller_helm_version.
  EOT
  type        = string
  default     = "v2.8.1"
}

variable "tags" {
  description = "Additional tags applied to IAM resources."
  type        = map(string)
  default     = {}
}
