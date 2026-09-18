include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "eks_controller" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/eks-controller.hcl"
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
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/otel-collector?ref=modules/otel-collector/v1.0.1"
}

inputs = {
  cluster_name      = dependency.eks.outputs.cluster_name
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  amp_workspace_arn    = dependency.observability.outputs.amp_workspace_arn
  amp_remote_write_url = dependency.observability.outputs.amp_remote_write_url

  tags = {
    Tier       = "cloud"
    CostCenter = "platform-engineering"
  }
}
