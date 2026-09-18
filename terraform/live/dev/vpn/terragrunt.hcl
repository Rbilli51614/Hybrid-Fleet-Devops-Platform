include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "cloud_vpc" {
  config_path = "../cloud-vpc"

  mock_outputs = {
    vpc_id                  = "vpc-00000000000000000"
    private_route_table_ids = ["rtb-00000000000000001"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "onprem_vpc" {
  config_path = "../onprem-vpc"

  mock_outputs = {
    vpc_id                  = "vpc-00000000000000005"
    public_subnet_ids       = ["subnet-00000000000000006"]
    private_route_table_ids = ["rtb-00000000000000007"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vpn?ref=modules/vpn/v1.0.0"
}

inputs = {
  name = "hybrid-fleet"

  cloud_vpc_id                  = dependency.cloud_vpc.outputs.vpc_id
  cloud_vpc_cidr                = "10.0.0.0/16" # must match terraform/live/dev/cloud-vpc's cidr_block
  cloud_private_route_table_ids = dependency.cloud_vpc.outputs.private_route_table_ids

  onprem_vpc_id                  = dependency.onprem_vpc.outputs.vpc_id
  onprem_vpc_cidr                = "10.1.0.0/16" # must match terraform/live/dev/onprem-vpc's cidr_block
  onprem_public_subnet_id        = dependency.onprem_vpc.outputs.public_subnet_ids[0]
  onprem_private_route_table_ids = dependency.onprem_vpc.outputs.private_route_table_ids

  tunnel_parameter_path = "/hybrid-fleet/vpn"

  tags = {
    Tier       = "onprem"
    CostCenter = "platform-engineering"
  }
}
