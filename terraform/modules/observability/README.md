# observability

Amazon Managed Prometheus (AMP) + its managed Alertmanager, Amazon Managed Grafana (AMG), and the CloudWatch-alarm-to-SNS half of the alerting path — the federated observability plane both K8s tiers' OpenTelemetry Collectors feed into (see [`terraform/modules/otel-collector`](../otel-collector/)) and CloudWatch feeds alongside. See [`docs/decision-stack.md`](../../../docs/decision-stack.md) for the Monitoring layer's rationale.

Versioned via git tags (`modules/observability/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Why CloudWatch alarms don't route through AMP's Alertmanager

The brief's shorthand — "CloudWatch + Alarms → Alertmanager → PagerDuty/OpsGenie" — reads like one pipeline, but Amazon Managed Prometheus's built-in Alertmanager only ever receives alerts *Prometheus itself evaluated* (from `aws_prometheus_rule_group_namespace`), not arbitrary CloudWatch alarms — there's no AWS-native bridge that feeds CloudWatch alarm state into it. So this module implements two parallel paths that both end up at the same place:

- **Prometheus-evaluated alerts** (`up == 0`, the example rules in `aws_prometheus_rule_group_namespace`) → AMP's managed Alertmanager (`aws_prometheus_alert_manager_definition`) → PagerDuty, if `pagerduty_integration_key` is set.
- **CloudWatch alarms** (EC2 status checks, VPN tunnel state — AWS-native metrics Prometheus never sees) → an SNS topic (`aws_sns_topic.alarms`) → PagerDuty/OpsGenie's own native SNS integration, or an email subscription for a portfolio-scale demo.

Both converge on the same destination; neither goes through the other. Worth knowing before assuming the diagram arrow is a literal single pipeline.

## The `pagerduty_integration_key = null` default used to crash `plan`/`apply` outright

Not a hypothetical — this is exactly what happened applying this stack for real with no key configured (this module's normal, out-of-the-box state, and its documented default). `locals.alertmanager_config_with_pagerduty` interpolated `var.pagerduty_integration_key` directly into a heredoc; Terraform evaluates *every* local in a `locals` block regardless of whether the ternary that picks between `alertmanager_config_with_pagerduty` and `alertmanager_config_default` (below) actually selects it, so `"${null}"` — invalid HCL, "Cannot include a null value in a string template" — blew up the whole plan even though that branch was never going to be used. Fixed by routing the interpolation through `coalesce(var.pagerduty_integration_key, "")` first, so the discarded branch is always evaluable even when it's empty. `terraform validate` never caught this (it doesn't fully evaluate variable defaults into locals the way a real plan does); only an actual plan against this module's own documented default surfaced it.

## Grafana authentication

`aws_grafana_workspace` here uses `AWS_SSO` (IAM Identity Center) authentication — the AWS-recommended default, and the only provider that doesn't need a separate SAML IdP. **IAM Identity Center must already be enabled in the account** (an account-level, not Terraform-managed, prerequisite) before this workspace is reachable. Pass `grafana_admin_sso_user_ids` (Identity Center user IDs, not IAM ARNs — find them via `aws identitystore list-users`) to actually grant someone in; an AWS_SSO-authenticated workspace with zero role associations has no way in for anyone.

## Example

```hcl
module "observability" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/observability?ref=modules/observability/v1.0.1"

  name = "hybrid-fleet"

  vpn_connection_id   = module.vpn.vpn_connection_id
  vpn_tunnel1_address = module.vpn.tunnel1_address
  vpn_tunnel2_address = module.vpn.tunnel2_address
  nexus_instance_id   = module.nexus.instance_id

  alarm_sns_subscription_email = "platform-oncall@example.com"
  grafana_admin_sso_user_ids   = ["a1b2c3d4-..."]
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — |
| `pagerduty_integration_key` | PagerDuty Events API v2 key for AMP's Alertmanager; `null` = alerts evaluated but not paged | `string` | `null` |
| `alarm_sns_subscription_email` | Email subscribed to the CloudWatch alarm SNS topic; `null` skips it | `string` | `null` |
| `vpn_connection_id` / `vpn_tunnel1_address` / `vpn_tunnel2_address` | From `terraform/modules/vpn`, for the TunnelState alarms | `string` | — |
| `nexus_instance_id` | From `terraform/modules/nexus-ec2`, for the status-check alarm | `string` | — |
| `grafana_admin_sso_user_ids` | IAM Identity Center user IDs granted Grafana ADMIN | `list(string)` | `[]` |
| `tags` | Extra tags applied to all resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `amp_workspace_id` / `amp_workspace_arn` | For scoping remote_write IAM policies |
| `amp_remote_write_url` | Feed into both tiers' OTel Collector config |
| `amp_query_endpoint` | For a manually-configured Grafana data source, or `promtool` |
| `grafana_workspace_endpoint` / `grafana_workspace_id` | Reach the workspace |
| `alarm_sns_topic_arn` | Subscribe PagerDuty's/OpsGenie's own SNS integration here |

## Not yet built

A Grafana data source pointed at the AMP workspace, and any dashboards, are **not** Terraform-managed — same "controller/infra is Terraform, workload-shaped config is applied separately" split as the rest of this repo (see [`docs/architecture.md`](../../../docs/architecture.md)), and a step further: Amazon Managed Grafana's data sources/dashboards are configured through Grafana's own API/console (or the community `grafana` Terraform provider, which needs its own API-key bootstrapping via `aws_grafana_workspace_service_account`) rather than the `aws` provider at all. Out of scope for now; a documented manual step (Grafana console → Add data source → Amazon Managed Prometheus → select this workspace) until dashboards-as-code earns its complexity.
