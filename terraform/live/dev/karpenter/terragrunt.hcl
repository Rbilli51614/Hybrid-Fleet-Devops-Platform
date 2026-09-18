include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "eks_controller" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/eks-controller.hcl"
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/karpenter?ref=modules/karpenter/v1.0.0"
}

inputs = {
  cluster_name      = dependency.eks.outputs.cluster_name
  cluster_endpoint  = dependency.eks.outputs.cluster_endpoint
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  tags = {
    Tier = "cloud"
  }
}
