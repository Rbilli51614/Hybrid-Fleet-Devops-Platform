include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "cloud_vpc" {
  config_path = "../cloud-vpc"

  mock_outputs = {
    vpc_cidr_block = "10.0.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "onprem_vpc" {
  config_path = "../onprem-vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000000000005"
    vpc_cidr_block      = "10.1.0.0/16"
    private_subnet_ids  = ["subnet-00000000000000003", "subnet-00000000000000004"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "dns" {
  config_path = "../dns"

  mock_outputs = {
    zone_id   = "Z00000000000000000MOCK"
    zone_name = "hybrid-fleet.internal"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  # Local relative path for now; switch to the tagged git source once
  # modules/nexus-ec2 has a release tag (see terraform/modules/nexus-ec2/README.md).
  source = "../../../modules/nexus-ec2"
}

inputs = {
  name = "hybrid-fleet"

  vpc_id             = dependency.onprem_vpc.outputs.vpc_id
  private_subnet_id  = dependency.onprem_vpc.outputs.private_subnet_ids[0]

  # Both K8s tiers can reach Nexus — the on-prem CIDR directly, the cloud
  # CIDR over the Phase 4 Site-to-Site VPN.
  allowed_cidr_blocks = [
    dependency.cloud_vpc.outputs.vpc_cidr_block,
    dependency.onprem_vpc.outputs.vpc_cidr_block,
  ]

  route53_zone_id  = dependency.dns.outputs.zone_id
  dns_record_name  = "nexus.${dependency.dns.outputs.zone_name}"

  tags = {
    Tier = "onprem"
  }
}
