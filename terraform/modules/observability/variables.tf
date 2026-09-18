variable "name" {
  description = "Name prefix for all resources created by this module."
  type        = string
}

variable "pagerduty_integration_key" {
  description = <<-EOT
    PagerDuty Events API v2 integration key for the Amazon Managed
    Prometheus Alertmanager's pagerduty_configs receiver. Left null by
    default (no real PagerDuty account in a portfolio context) — the
    Alertmanager config is still valid YAML with a null receiver in that
    case, it just silently swallows matched alerts instead of paging
    anyone. See this module's README for the OpsGenie alternative.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "alarm_sns_subscription_email" {
  description = "Email address to subscribe to the CloudWatch alarm SNS topic. Null skips the subscription (the topic and alarms still exist)."
  type        = string
  default     = null
}

variable "vpn_connection_id" {
  description = "VPN connection ID (from terraform/modules/vpn's vpn_connection_id output), for the TunnelState alarms."
  type        = string
}

variable "vpn_tunnel1_address" {
  description = "Tunnel 1 outside address (from terraform/modules/vpn's tunnel1_address output)."
  type        = string
}

variable "vpn_tunnel2_address" {
  description = "Tunnel 2 outside address (from terraform/modules/vpn's tunnel2_address output)."
  type        = string
}

variable "nexus_instance_id" {
  description = "Nexus instance ID (from terraform/modules/nexus-ec2's instance_id output), for the status-check alarm."
  type        = string
}

variable "grafana_admin_sso_user_ids" {
  description = <<-EOT
    IAM Identity Center (AWS SSO) user IDs to grant Grafana workspace ADMIN
    — not IAM ARNs; find them via `aws identitystore list-users` against
    your Identity Center instance. Left empty by default; populate before
    relying on this workspace, since an AWS_SSO-authenticated workspace
    with no role associations has no way in.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
