include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "cloud_vpc" {
  config_path = "../cloud-vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "onprem_vpc" {
  config_path = "../onprem-vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000000000005"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  # Local relative path for now; switch to the tagged git source once
  # modules/private-dns has a release tag (see terraform/modules/private-dns/README.md).
  source = "../../../modules/private-dns"
}

inputs = {
  zone_name          = "hybrid-fleet.internal"
  primary_vpc_id     = dependency.cloud_vpc.outputs.vpc_id
  additional_vpc_ids = [dependency.onprem_vpc.outputs.vpc_id]

  tags = {
    Tier = "shared"
  }
}
