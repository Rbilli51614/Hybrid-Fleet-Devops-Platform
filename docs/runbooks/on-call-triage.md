# Runbook: On-Call Triage

First-response steps for an alert fired from either K8s tier or the shared infra underneath them. Start here, then follow the link to a dedicated runbook (currently just [`nexus-backup-restore.md`](nexus-backup-restore.md)) when one exists for the specific alert.

## Where alerts come from

[`terraform/modules/observability`](../../terraform/modules/observability/) implements two parallel alerting paths — see that module's README for why they're parallel, not one pipeline:

| Path | Evaluates | Routes to |
|---|---|---|
| Amazon Managed Prometheus's managed Alertmanager | Rules in `aws_prometheus_rule_group_namespace` — `up == 0` (`TargetDown`), `system_memory_utilization > 0.9` (`HostHighMemory`) | PagerDuty, if `pagerduty_integration_key` is set; otherwise evaluated but not paged |
| CloudWatch alarms → SNS (`aws_sns_topic.alarms`) | AWS-native signals Prometheus never sees: EC2 status checks, VPN tunnel state | PagerDuty/OpsGenie's native SNS integration, or the email subscription (`alarm_sns_subscription_email`) |

Both tiers' [`otel-collector`](../../terraform/modules/otel-collector/) feed the same AMP workspace via `remote_write`, so `TargetDown`/`HostHighMemory` can fire for a host on *either* cluster — check `{{ $labels.instance }}` in the alert before assuming which tier.

## First response, by alert

### `TargetDown` (Prometheus `up == 0`)

A host's OTel Collector has stopped exporting for 5+ minutes — the collector process died, the host is unreachable, or (VM tier only) its sigv4-signed remote_write is failing auth.

1. Identify the tier from `{{ $labels.instance }}` and the Grafana dashboard (see below).
2. **EKS tier:**
   ```bash
   aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1
   kubectl get pods -n otel-collector-system   # or wherever it's installed — see kubernetes/base/otel-collector/
   kubectl logs -n otel-collector-system -l app.kubernetes.io/name=opentelemetry-collector --tail=100
   ```
3. **VM tier** (no kubeconfig without first configuring VPN/DNS access — SSM works regardless):
   ```bash
   aws ssm start-session --target <instance-id>
   sudo systemctl status otel-collector
   sudo journalctl -u otel-collector --since "-30 min"
   ```
   A VM-tier auth failure specifically (`403`/`AccessDenied` in the logs) points at the instance's IAM role missing the AMP remote-write grant — see [`docs/architecture.md`](../architecture.md#federated-observability-one-shared-pipeline-file-two-render-mechanisms) for why that grant depends on `../observability` existing first.
4. If the host itself is unreachable (SSM session won't start, `kubectl` shows `NotReady`), treat it as a node-health issue, not a collector issue — check the node's EC2/ASG status.

### `HostHighMemory` (`system_memory_utilization > 0.9` for 10m)

1. Confirm it's sustained, not a spike, in Grafana.
2. SSM in (as above) or `kubectl top pod`/`node` if it's a workload-level cause on EKS.
3. On the VM tier specifically, a control-plane node pinned this way for a sustained period is worth escalating faster than a worker — there's exactly one (per role, per Phase 3's ASG sizing), no Karpenter-style automatic replacement.

### `<name>-nexus-status-check-failed`

Nexus's single EC2 instance failed an AWS status check (system or instance) for 10+ minutes.

1. Check the instance in the console/CLI: `aws ec2 describe-instance-status --instance-ids <nexus-instance-id>`.
2. A **system** status check failure is AWS-infra-side (underlying host); usually resolves itself or needs an instance stop/start (not reboot) to migrate to new hardware — the EBS data volume survives this (see [`docs/architecture.md`](../architecture.md#nexus-a-pet-not-livestock-and-thats-deliberate)).
3. An **instance** status check failure is OS/instance-side. If the instance needs replacing, re-apply `terraform/live/dev/nexus` — the data volume reattaches automatically. Then go to [`nexus-backup-restore.md`](nexus-backup-restore.md) if the volume itself is also gone.
4. Nexus being down blocks both K8s tiers' builds (it's the shared artifact repo) — treat this as higher severity than a single-host alert would otherwise suggest.

### `<name>-vpn-tunnel1-down` / `<name>-vpn-tunnel2-down`

One of the two Site-to-Site VPN tunnels between the cloud and on-prem VPCs is down for 10+ minutes.

1. **One tunnel down, the other up:** the VPN connection tolerates this (AWS's side has two tunnels precisely for this) — not an outage, but page-worthy because you're down to zero redundancy. No cross-VPC traffic is actually interrupted yet.
2. **Both tunnels down:** this IS an outage — anything that depends on the tunnel breaks: Nexus reachability from the cloud tier, the VM tier's AMP remote-write (if routed over the tunnel), cross-VPC DNS resolution.
3. Check the strongSwan side first — it's the self-managed half of this tunnel, unlike everything else AWS-managed in this repo:
   ```bash
   aws ssm start-session --target <vpn-gateway-instance-id>
   sudo ipsec status
   sudo journalctl -u strongswan --since "-30 min"
   ```
4. If strongSwan looks healthy but the tunnel is still down, check the AWS side: `aws ec2 describe-vpn-connections --vpn-connection-ids <vpn-connection-id>` for the tunnel status AWS itself sees, and confirm the customer gateway's public IP (the VPN instance's EIP) hasn't changed.
5. See [`docs/architecture.md`](../architecture.md#the-site-to-site-vpn-a-real-tunnel-not-a-diagram-placeholder) and [`terraform/modules/vpn/README.md`](../../terraform/modules/vpn/) for the tunnel's actual topology before assuming a fix.

## Grafana

Amazon Managed Grafana workspace (`terraform/modules/observability`'s `aws_grafana_workspace`) — reach it via the AWS console (Workspace URL) or `terragrunt output grafana_workspace_endpoint` from `terraform/live/dev/observability`. Sign-in is IAM Identity Center (AWS_SSO); see that module's README if you're not in `grafana_admin_sso_user_ids` and can't get in. **The Prometheus/CloudWatch data sources and dashboards are a manual, documented setup step, not Terraform-managed** — see that module's "Not yet built" section — so don't assume a dashboard exists for a given alert until you've confirmed one was actually built.

## Escalation

- **Nexus down** or **both VPN tunnels down**: page immediately, both tiers' CI/CD is affected.
- **Single alert, single host, one tier**: standard on-call response time; the other tier is unaffected proof that this isn't a platform-wide event.
- **Alert firing with no obvious cause after the steps above**: check whether it's actually a Terraform drift issue first (`terragrunt plan` against the relevant stack, read-only) before assuming it's a runtime incident — a manually-reverted change or a failed apply can look identical to a real outage from an alert alone.

## Known limitations

- **No dashboards-as-code, no alert-to-runbook automation.** This document is the correlation layer right now — a human reads the alert name and comes here. See [`docs/pitfalls.md`](../pitfalls.md) for when that stops scaling.
- **No automated alert testing.** Like the Nexus restore runbook, this has never been exercised against a real firing alert (no live AWS account in this repo) — the alarm names, thresholds, and metric dimensions above are read directly from `terraform/modules/observability/main.tf`, not assumed.
- **Two independent alerting paths, easy to forget.** A responder used to a single pipeline (alert → one Alertmanager → one destination) can reasonably assume CloudWatch alarms route through AMP's Alertmanager — they don't. See that module's README before "fixing" what looks like a missing Alertmanager route for a CloudWatch-sourced alert.
