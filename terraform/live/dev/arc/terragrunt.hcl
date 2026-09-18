include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "eks_controller" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/eks-controller.hcl"
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/arc?ref=modules/arc/v1.0.1"
}

inputs = {
  cluster_name      = dependency.eks.outputs.cluster_name
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  # Leave null until a team actually needs runner-pod AWS access (e.g. ECR
  # push during a build job); see terraform/modules/arc/README.md.
  runner_irsa_policy_json = null

  tags = {
    Tier       = "cloud"
    CostCenter = "platform-engineering"
  }
}
