include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpn" {
  config_path = "../vpn"

  mock_outputs = {
    vpn_connection_id = "vpn-00000000000000000"
    tunnel1_address   = "203.0.113.1"
    tunnel2_address   = "203.0.113.2"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "nexus" {
  config_path = "../nexus"

  mock_outputs = {
    instance_id = "i-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/observability?ref=modules/observability/v1.0.1"
}

inputs = {
  name = "hybrid-fleet"

  vpn_connection_id   = dependency.vpn.outputs.vpn_connection_id
  vpn_tunnel1_address = dependency.vpn.outputs.tunnel1_address
  vpn_tunnel2_address = dependency.vpn.outputs.tunnel2_address
  nexus_instance_id   = dependency.nexus.outputs.instance_id

  # Fill in before relying on paging/Grafana access — see this module's
  # README ("Why CloudWatch alarms don't route through AMP's Alertmanager"
  # and "Grafana authentication").
  pagerduty_integration_key    = null
  alarm_sns_subscription_email = null
  grafana_admin_sso_user_ids   = []

  tags = {
    Tier       = "shared"
    CostCenter = "platform-engineering"
  }
}
