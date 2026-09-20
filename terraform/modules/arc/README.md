# arc

Installs the GitHub Actions Runner Controller (`gha-runner-scale-set-controller`) via Helm, and provisions a Secrets Manager container for the GitHub App credentials runners register with. The per-repo/org runner scale set itself — the thing that actually says "these runners serve this repo" — is deliberately **not** managed here; see [`kubernetes/eks/arc/`](../../../kubernetes/eks/arc/), same Terraform/kubectl split used for [Karpenter's NodePool](../../../kubernetes/eks/karpenter/).

Versioned via git tags (`modules/arc/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

Depends on outputs from [`eks-cluster`](../eks-cluster/) and calls [`iam-irsa`](../iam-irsa/) internally when `attach_runner_irsa_policy` is `true` — see [`iam-irsa`](../iam-irsa/)'s README for why that's a separate flag from `runner_irsa_policy_json` itself.

## Registering runners (one-time, manual — GitHub App credentials are secrets)

1. [Create a GitHub App](https://docs.github.com/en/apps/creating-github-apps) on the org (or a repo) with the runner-registration permissions ARC needs, generate a private key, and note the App ID and Installation ID.
2. Populate the placeholder secret this module created:
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id "$(terragrunt output -raw github_app_secret_name)" \
     --secret-string "$(jq -n --arg id "$APP_ID" --arg inst "$INSTALLATION_ID" --arg key "$(cat private-key.pem)" \
       '{github_app_id: $id, github_app_installation_id: $inst, github_app_private_key: $key}')"
   ```
3. Create the `arc-runners` namespace. Nothing else in this flow creates it: this module's own `helm_release` only sets `create_namespace = true` on the *controller's* namespace (`arc-systems`), `runner_irsa` (when enabled) only *references* `runners_namespace` for an IAM trust-policy condition rather than creating anything Kubernetes-side, and the scale set's own `helm install` in [`kubernetes/eks/arc/README.md`](../../../kubernetes/eks/arc/README.md) doesn't pass `--create-namespace` — by design, since it needs the secret below to already exist in that namespace by the time it runs.
   ```bash
   kubectl create namespace arc-runners
   ```
4. Sync the secret into the Kubernetes secret the scale set expects (no External Secrets Operator yet — see "Not yet built" below). Build it as a manifest piped straight into `kubectl apply -f -`, not `--from-literal` flags via `xargs`: the private key is multi-line PEM, `xargs` splits on *any* whitespace including embedded newlines, and a real run tore `-----END RSA PRIVATE KEY-----` out as its own word — which `kubectl` then read as a flag and rejected with `bad flag syntax: -----END`.
   ```bash
   aws secretsmanager get-secret-value --secret-id "$(terragrunt output -raw github_app_secret_name)" \
     --query SecretString --output text | \
   jq '{
     apiVersion: "v1",
     kind: "Secret",
     metadata: { name: "arc-github-app", namespace: "arc-runners" },
     type: "Opaque",
     stringData: .
   }' | \
   kubectl apply -f -
   ```
5. Install the runner scale set — see [`kubernetes/eks/arc/README.md`](../../../kubernetes/eks/arc/README.md).

## Example

```hcl
module "arc" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/arc?ref=modules/arc/v1.0.0"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # Optional: let runner pods push to ECR without static credentials. Note
  # attach_runner_irsa_policy is required alongside this — see below.
  attach_runner_irsa_policy = true
  runner_irsa_policy_json   = data.aws_iam_policy_document.runner_ecr_push.json
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name | `string` | — |
| `oidc_provider_arn` / `oidc_provider_url` | Cluster IRSA trust anchor | `string` | — |
| `controller_namespace` | Namespace for the controller | `string` | `"arc-systems"` |
| `runners_namespace` | Namespace for runner scale sets/pods | `string` | `"arc-runners"` |
| `controller_helm_version` | Controller Helm chart version | `string` | `"0.9.3"` |
| `github_app_secret_name` | Secrets Manager secret name | `string` | `"<cluster_name>-arc-github-app"` |
| `attach_runner_irsa_policy` | Whether to create the runner IRSA role at all | `bool` | `false` |
| `runner_irsa_policy_json` | Inline policy for runner pods' AWS access, used only when `attach_runner_irsa_policy` is `true` | `string` | `null` |
| `runner_service_account_name` | Service account the IRSA role trusts | `string` | `"arc-runner"` |
| `tags` | Extra tags on IAM/Secrets Manager resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `github_app_secret_arn` / `github_app_secret_name` | The placeholder secret — populate out of band |
| `runner_irsa_role_arn` | Runner pods' IRSA role ARN, or `null` |
| `controller_namespace` / `runners_namespace` | For wiring the Phase 2 scale-set Helm install |

**Not yet built:** an External Secrets Operator sync from Secrets Manager straight into the runner namespace (today's flow is the manual `kubectl create secret` above). Worth adding once a second AWS-backed secret shows up elsewhere in the fleet and the sync logic is worth sharing.
