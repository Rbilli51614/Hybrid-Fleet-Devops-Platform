terraform {
  required_version = ">= 1.7.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    # This module's own resources never touch AWS — but the same pattern
    # used by karpenter/arc/alb-ingress-controller applies here too: the
    # live stack generates a helm_provider.tf alongside this module's files
    # (Terragrunt merges them into one working directory) that uses
    # data.aws_eks_cluster_auth to authenticate. Declaring it here, not in
    # a second generate block, keeps every EKS-side controller module
    # consistent.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
