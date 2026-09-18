# Root Terragrunt config, included by every stack under terraform/live/**.
#
# Bootstrap order:
#   1. Apply terraform/live/global/state-backend directly with plain `terraform`
#      (it creates the S3 bucket + DynamoDB table this file references).
#   2. Everything under terraform/live/dev/** and future envs runs via
#      `terragrunt` and picks up remote state + provider config from here.

terraform_binary = "terraform"

locals {
  aws_region  = "us-east-1"
  environment = basename(dirname(get_terragrunt_dir()))

  state_bucket = "hybrid-fleet-devops-platform-tfstate"
  lock_table   = "hybrid-fleet-terraform-locks"
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = local.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = {
      Project     = "hybrid-fleet-devops-platform"
      ManagedBy   = "terragrunt"
      Environment = "${local.environment}"
    }
  }
}
EOF
}

# No generate "versions" block here: every module under terraform/modules/**
# already declares its own required_version/required_providers in versions.tf.
# Generating a second one at the root would collide with it in the
# .terragrunt-cache working copy.

inputs = {
  aws_region  = local.aws_region
  environment = local.environment
}
