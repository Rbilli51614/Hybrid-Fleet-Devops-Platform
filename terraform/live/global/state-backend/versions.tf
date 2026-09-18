terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Intentionally local state: this stack creates the remote state backend
  # itself, so it cannot depend on the backend it provisions.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "hybrid-fleet-devops-platform"
      ManagedBy = "terraform"
      Stack     = "global/state-backend"
    }
  }
}
