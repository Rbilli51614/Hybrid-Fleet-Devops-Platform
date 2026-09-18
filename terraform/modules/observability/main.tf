# ---------------------------------------------------------------------------
# Amazon Managed Prometheus (AMP) — the federated metrics store both
# tiers' OpenTelemetry Collectors remote_write into. See
# terraform/modules/otel-collector.
# ---------------------------------------------------------------------------

resource "aws_prometheus_workspace" "this" {
  alias = "${var.name}-amp"
  tags  = var.tags
}

# A couple of demonstrable alerting rules, not an exhaustive rulebook —
# up == 0 (target down) is the canonical first Prometheus alert; the
# second shows a rule reading a metric shape the otel-collector's
# hostmetrics receiver actually produces on both tiers.
resource "aws_prometheus_rule_group_namespace" "this" {
  workspace_id = aws_prometheus_workspace.this.id
  name         = "${var.name}-alerts"

  data = <<-EOT
    groups:
      - name: hybrid-fleet-core
        rules:
          - alert: TargetDown
            expr: up == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "{{ $labels.instance }} has been unreachable for 5m"
          - alert: HostHighMemory
            expr: system_memory_utilization > 0.9
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "{{ $labels.instance }} memory utilization above 90% for 10m"
  EOT
}

locals {
  alertmanager_config_with_pagerduty = <<-EOT
    route:
      receiver: pagerduty
    receivers:
      - name: pagerduty
        pagerduty_configs:
          - service_key: ${var.pagerduty_integration_key}
  EOT

  # No PagerDuty integration key configured — alerts are evaluated and
  # visible in the AMP workspace/Grafana, but not paged anywhere yet. Set
  # var.pagerduty_integration_key to wire up real paging.
  alertmanager_config_default = <<-EOT
    route:
      receiver: default
    receivers:
      - name: default
  EOT
}

# Amazon Managed Prometheus's own managed Alertmanager — not a separate
# self-hosted component. See this module's README for why CloudWatch
# alarms (below) route to PagerDuty/OpsGenie directly via SNS rather than
# through this: Alertmanager only ever receives alerts Prometheus itself
# evaluated, not arbitrary CloudWatch alarms.
resource "aws_prometheus_alert_manager_definition" "this" {
  workspace_id = aws_prometheus_workspace.this.id

  definition = var.pagerduty_integration_key != null ? local.alertmanager_config_with_pagerduty : local.alertmanager_config_default
}

# ---------------------------------------------------------------------------
# Amazon Managed Grafana (AMG)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "grafana_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  name               = "${var.name}-grafana"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume_role.json
  tags               = var.tags
}

# Standard read-only data-source access for the two source types this
# workspace is configured for (see aws_grafana_workspace.data_sources
# below) — no write/mutate actions against either service.
data "aws_iam_policy_document" "grafana_data_sources" {
  statement {
    sid = "Prometheus"
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:QueryMetrics",
      "aps:GetLabels",
      "aps:GetSeries",
      "aps:GetMetricMetadata",
    ]
    resources = ["*"]
  }

  statement {
    sid = "CloudWatch"
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport",
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "grafana_data_sources" {
  name   = "${var.name}-grafana-data-sources"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.grafana_data_sources.json
}

resource "aws_grafana_workspace" "this" {
  name                     = "${var.name}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]

  tags = var.tags
}

resource "aws_grafana_role_association" "admins" {
  count = length(var.grafana_admin_sso_user_ids) > 0 ? 1 : 0

  workspace_id = aws_grafana_workspace.this.id
  role         = "ADMIN"
  user_ids     = var.grafana_admin_sso_user_ids
}

# ---------------------------------------------------------------------------
# CloudWatch alarms -> SNS -> PagerDuty/OpsGenie
#
# Deliberately parallel to, not routed through, AMP's Alertmanager above —
# see this module's README.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_sns_subscription_email != null ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_sns_subscription_email
}

resource "aws_cloudwatch_metric_alarm" "nexus_status_check" {
  alarm_name          = "${var.name}-nexus-status-check-failed"
  alarm_description   = "Nexus instance failed an EC2 status check (system or instance)."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = var.nexus_instance_id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "vpn_tunnel1_down" {
  alarm_name          = "${var.name}-vpn-tunnel1-down"
  alarm_description   = "Site-to-Site VPN tunnel 1 is down."
  namespace           = "AWS/VPN"
  metric_name         = "TunnelState"
  dimensions          = { VpnId = var.vpn_connection_id, TunnelIpAddress = var.vpn_tunnel1_address }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "vpn_tunnel2_down" {
  alarm_name          = "${var.name}-vpn-tunnel2-down"
  alarm_description   = "Site-to-Site VPN tunnel 2 is down."
  namespace           = "AWS/VPN"
  metric_name         = "TunnelState"
  dimensions          = { VpnId = var.vpn_connection_id, TunnelIpAddress = var.vpn_tunnel2_address }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}
