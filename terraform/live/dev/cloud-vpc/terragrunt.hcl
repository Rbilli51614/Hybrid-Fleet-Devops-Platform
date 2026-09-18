include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Local relative path for now (fast local iteration on modules that don't
  # have a release tag yet). Once the vpc module is tagged, switch to:
  #   source = "git::https://github.com/<org>/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vpc?ref=modules/vpc/v1.0.0"
  source = "../../../modules/vpc"
}

inputs = {
  name       = "hybrid-fleet-cloud"
  cidr_block = "10.0.0.0/16"
  azs        = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  single_nat_gateway = true
  eks_cluster_name   = "hybrid-fleet-eks"

  tags = {
    Tier = "cloud"
  }
}
