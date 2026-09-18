# otel-collector

Installs the OpenTelemetry Collector Helm chart on EKS, with an IRSA role scoped to exactly one permission — `aps:RemoteWrite` on the Amazon Managed Prometheus workspace ARN — since SigV4-signed `prometheusremotewrite` export is all this collector does. The VM-tier counterpart is [`ansible/roles/otel-collector`](../../../ansible/roles/otel-collector/), authenticating with the node's own EC2 instance role via IMDS instead of IRSA (that tier has no OIDC provider to attach IRSA to), granted the same permission by `terraform/modules/vm-k8s-asg`'s `amp_workspace_arn` input.

Versioned via git tags (`modules/otel-collector/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## The shared pipeline config

Both this module and the Ansible role render the *same* file — [`kubernetes/base/otel-collector/values.yaml.tmpl`](../../../kubernetes/base/otel-collector/values.yaml.tmpl) — substituting only `amp_remote_write_url` and `aws_region`. One receiver (`hostmetrics`), one exporter (`prometheusremotewrite` via `sigv4auth`), same on both tiers. This is deliberately the same "one shared file, two render mechanisms" pattern used for Gatekeeper's `ConstraintTemplate`s, just templated instead of applied verbatim, since the SigV4 region/endpoint genuinely differ from a hardcoded value per environment where the Gatekeeper policies don't need any per-environment substitution at all.

## Two chart requirements a real apply caught, `helm template`/`terraform validate` didn't

Pinning `otel_collector_helm_version` doesn't freeze what that pinned version *requires* — both of these are hard failures the `opentelemetry-collector` chart itself enforces via its own template logic (a `{{ fail ... }}`-style check in `NOTES.txt`), not something Terraform, Helm's schema validation, or a dry-run linter catches ahead of time:

- **`image.repository` must be set explicitly** — the chart ships no default any more. It has to be `otel/opentelemetry-collector-contrib`, not the chart's own suggested core `otel/opentelemetry-collector` image: `sigv4auth` and `prometheusremotewrite`, both load-bearing in this pipeline, only exist in the contrib distribution.
- **A `health_check` extension is mandatory**, listed in both `config.extensions` and `config.service.extensions` — unrelated to anything this pipeline's metrics path actually needs; it's purely the chart's own liveness/readiness contract.

Verified directly with `helm template` against the real pinned chart version before either fix shipped, not assumed from the error text alone.

## Example

```hcl
module "otel_collector" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/otel-collector?ref=modules/otel-collector/v1.0.2"

  cluster_name          = module.eks.cluster_name
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  amp_workspace_arn     = module.observability.amp_workspace_arn
  amp_remote_write_url  = module.observability.amp_remote_write_url
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name | `string` | — |
| `oidc_provider_arn` / `oidc_provider_url` | Cluster IRSA trust anchor | `string` | — |
| `amp_workspace_arn` | Scopes the `aps:RemoteWrite` IAM permission | `string` | — |
| `amp_remote_write_url` | Rendered into the shared values template | `string` | — |
| `aws_region` | Rendered into the shared values template's `sigv4auth` extension | `string` | `"us-east-1"` |
| `namespace` | Namespace for the collector | `string` | `"otel-collector-system"` |
| `otel_collector_helm_version` | Chart version — must match the Ansible role's default | `string` | `"0.108.0"` |
| `tags` | Extra tags on the IRSA role | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `controller_role_arn` | IRSA role ARN |
| `namespace` | For reference (e.g. `kubectl logs -n <namespace>`) |
