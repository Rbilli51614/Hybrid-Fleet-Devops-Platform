include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "onprem_vpc" {
  config_path = "../onprem-vpc"

  # Lets `terragrunt validate`/`plan` run before onprem-vpc has ever been
  # applied. Real values are used automatically once it has state.
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000003", "subnet-00000000000000004"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Phase 8 (observability) added this dependency after this stack already
# existed — expected and fine: Terragrunt orders by the dependency graph,
# not by phase number, so `terragrunt run-all apply` still sequences this
# correctly even though observability's own directory number is higher.
# On an already-applied cluster, just re-apply this stack once
# ../observability exists to pick up the new grant.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    amp_workspace_arn = "arn:aws:aps:us-east-1:000000000000:workspace/ws-00000000-0000-0000-0000-000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vm-k8s-asg?ref=modules/vm-k8s-asg/v1.0.0"
}

inputs = {
  name         = "hybrid-fleet-vm-k8s"
  cluster_name = "hybrid-fleet-vm-k8s"

  vpc_id     = dependency.onprem_vpc.outputs.vpc_id
  subnet_ids = dependency.onprem_vpc.outputs.private_subnet_ids

  amp_workspace_arn = dependency.observability.outputs.amp_workspace_arn

  # Single control-plane node: no HA/load-balanced control plane here — see
  # terraform/modules/vm-k8s-asg/README.md for why that's an accepted
  # limitation at this scale, not an oversight.
  node_groups = {
    control-plane = {
      role          = "control-plane"
      instance_type = "t3.medium"
      desired_size  = 1
      min_size      = 1
      max_size      = 1
    }
    worker = {
      role          = "worker"
      instance_type = "t3.medium"
      desired_size  = 2
      min_size      = 2
      max_size      = 2
    }
  }

  tags = {
    Tier       = "onprem"
    CostCenter = "platform-engineering"
  }
}
