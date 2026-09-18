include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "eks_controller" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/eks-controller.hcl"
}

dependency "cloud_vpc" {
  config_path = "../cloud-vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/alb-ingress-controller?ref=modules/alb-ingress-controller/v1.0.1"
}

inputs = {
  cluster_name      = dependency.eks.outputs.cluster_name
  vpc_id            = dependency.cloud_vpc.outputs.vpc_id
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  tags = {
    Tier       = "cloud"
    CostCenter = "platform-engineering"
  }
}
