# kubernetes/base/otel-collector

One file, two render mechanisms — the actual pipeline config both K8s tiers' OpenTelemetry Collector installs share.

`values.yaml.tmpl` uses Terraform `templatefile()` `${var}` placeholders, not Jinja. [`terraform/modules/otel-collector`](../../../terraform/modules/otel-collector/) (EKS) renders it with `templatefile()` directly; [`ansible/roles/otel-collector`](../../../ansible/roles/otel-collector/) (VM tier) renders the *same literal file* by reading it with the `file` lookup and applying Jinja's `replace` filter for the same two placeholders — a plain string substitution, not a separate near-duplicate `.j2` copy that could silently drift from this one. Verified both mechanisms produce byte-identical output for the same two substituted values before committing this file.

Two placeholders, substituted per-environment (everything else is identical):

- `${amp_remote_write_url}` — from `terraform/modules/observability`'s `amp_remote_write_url` output.
- `${aws_region}` — the region the AMP workspace lives in.

## Pipeline

- **Receiver:** `hostmetrics` (CPU, memory, disk, network, filesystem) — chosen over a Kubernetes-specific scrape config deliberately, since it works identically on both tiers without depending on EKS-vs-kubeadm differences in service discovery.
- **Exporter:** `prometheusremotewrite`, authenticated via the `sigv4auth` extension — on EKS, that resolves to the pod's IRSA role; on the VM tier, to the EC2 instance's own IAM role via IMDS. Same SDK credential-chain mechanism either way, different identity behind it.

Not yet built: trace/log pipelines (CloudWatch Logs/X-Ray exporters) — this repo's observability story currently covers metrics only. A natural next extension once a real workload exists to generate traces worth collecting.
