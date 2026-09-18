include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "cloud_vpc" {
  config_path = "../cloud-vpc"

  # Lets `terragrunt validate`/`plan` run before cloud-vpc has ever been
  # applied. Real values are used automatically once it has state.
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/eks-cluster?ref=modules/eks-cluster/v1.0.0"
}

inputs = {
  cluster_name       = "hybrid-fleet-eks"
  kubernetes_version = "1.30"

  vpc_id     = dependency.cloud_vpc.outputs.vpc_id
  subnet_ids = dependency.cloud_vpc.outputs.private_subnet_ids

  # Fill in with your own IAM user/role ARN before applying, or rely on
  # bootstrap_cluster_creator_admin_permissions (the applying principal
  # already gets cluster-admin automatically).
  admin_principal_arns = []

  core_node_instance_types = ["t3.medium"]
  core_node_desired_size   = 2
  core_node_min_size       = 2
  core_node_max_size       = 3

  tags = {
    Tier = "cloud"
  }
}
