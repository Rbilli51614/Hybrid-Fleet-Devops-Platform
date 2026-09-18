output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID."
  value       = aws_prometheus_workspace.this.id
}

output "amp_workspace_arn" {
  description = "Amazon Managed Prometheus workspace ARN — scope IRSA/instance-role remote_write policies to this, not \"*\"."
  value       = aws_prometheus_workspace.this.arn
}

output "amp_remote_write_url" {
  description = "Remote-write endpoint both tiers' OpenTelemetry Collectors send metrics to — see terraform/modules/otel-collector."
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "amp_query_endpoint" {
  description = "Query endpoint (e.g. for a Grafana data source pointed here manually, or promtool)."
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "grafana_workspace_endpoint" {
  description = "URL of the Grafana workspace."
  value       = aws_grafana_workspace.this.endpoint
}

output "grafana_workspace_id" {
  description = "Grafana workspace ID."
  value       = aws_grafana_workspace.this.id
}

output "alarm_sns_topic_arn" {
  description = "SNS topic CloudWatch alarms publish to — subscribe PagerDuty's/OpsGenie's own SNS integration endpoint here directly, alongside or instead of alarm_sns_subscription_email."
  value       = aws_sns_topic.alarms.arn
}
