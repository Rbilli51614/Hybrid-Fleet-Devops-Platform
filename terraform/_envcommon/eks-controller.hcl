# Shared by every EKS-side controller stack that has to be its own
# Terragrunt unit (separate from ../eks) purely so its helm provider can
# authenticate against a cluster that already exists — karpenter, arc,
# alb-ingress-controller, opa-gatekeeper, otel-collector — see
# docs/architecture.md#why-eks-and-karpenter-are-separate-terragrunt-stacks.
#
# Note on the name: Terragrunt's "_envcommon" pattern is usually shown
# solving cross-*environment* duplication (the same component's config
# repeated across dev/staging/prod). This repo only has one environment,
# so that's not the duplication here — this file exists because the exact
# same dependency + generate block was copy-pasted verbatim into five
# sibling stacks. Same mechanism (an included, shared .hcl fragment),
# applied to a different axis of duplication.
#
# Include AFTER root.hcl in each consuming terragrunt.hcl:
#
#   include "root" { path = find_in_parent_folders("root.hcl") }
#   include "eks_controller" {
#     path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/eks-controller.hcl"
#   }
#
# Makes `dependency.eks.outputs.*` available to the including file's own
# `inputs` block — mocks all five outputs unconditionally so a stack that
# only needs three (e.g. opa-gatekeeper, which has no IRSA role) doesn't
# need its own copy of this block just to trim two unused keys.

dependency "eks" {
  config_path = "../eks"

  # Lets `terragrunt validate`/`plan` run before the eks stack has ever
  # been applied. Real values are used automatically once it has state.
  mock_outputs = {
    cluster_name                       = "hybrid-fleet-eks"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw==" # base64("mock")
    oidc_provider_arn                  = "arn:aws:iam::000000000000:oidc-provider/mock.oidc.eks.amazonaws.com/id/MOCK"
    oidc_provider_url                  = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

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
