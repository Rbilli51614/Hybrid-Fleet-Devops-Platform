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

dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    amp_workspace_arn    = "arn:aws:aps:us-east-1:000000000000:workspace/ws-00000000-0000-0000-0000-000000000000"
    amp_remote_write_url = "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-mock/api/v1/remote_write"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  # Local relative path for now; switch to the tagged git source once
  # modules/otel-collector has a release tag (see its README.md).
  source = "../../../modules/otel-collector"
}

# Separate Terragrunt unit from ../eks for the same reason as
# ../karpenter, ../arc, ../alb-ingress-controller, and ../opa-gatekeeper:
# the helm provider needs a cluster that already exists.
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
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  amp_workspace_arn    = dependency.observability.outputs.amp_workspace_arn
  amp_remote_write_url = dependency.observability.outputs.amp_remote_write_url

  tags = {
    Tier = "cloud"
  }
}
