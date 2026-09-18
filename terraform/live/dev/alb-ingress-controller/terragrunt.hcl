include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "hybrid-fleet-eks"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw==" # base64("mock")
    oidc_provider_arn                  = "arn:aws:iam::000000000000:oidc-provider/mock.oidc.eks.amazonaws.com/id/MOCK"
    oidc_provider_url                  = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "cloud_vpc" {
  config_path = "../cloud-vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  # Local relative path for now; switch to the tagged git source once
  # modules/alb-ingress-controller has a release tag (see its README.md).
  source = "../../../modules/alb-ingress-controller"
}

# Separate Terragrunt unit from ../eks for the same reason as ../karpenter
# and ../arc: the helm provider needs a cluster that already exists.
generate "helm_provider" {
  path      = "helm_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
data "aws_eks_cluster_auth" "this" {
  name = "${dependency.eks.outputs.cluster_name}"
}

provider "helm" {
  kubernetes {
    host                   = "${dependency.eks.outputs.cluster_endpoint}"
    cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
EOF
}

inputs = {
  cluster_name      = dependency.eks.outputs.cluster_name
  vpc_id            = dependency.cloud_vpc.outputs.vpc_id
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  tags = {
    Tier = "cloud"
  }
}
