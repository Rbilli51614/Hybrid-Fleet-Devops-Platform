# arc

Installs the GitHub Actions Runner Controller (`gha-runner-scale-set-controller`) via Helm, and provisions a Secrets Manager container for the GitHub App credentials runners register with. The per-repo/org runner scale set itself — the thing that actually says "these runners serve this repo" — is deliberately **not** managed here; see [`kubernetes/eks/arc/`](../../../kubernetes/eks/arc/), same Terraform/kubectl split used for [Karpenter's NodePool](../../../kubernetes/eks/karpenter/).

Versioned via git tags (`modules/arc/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

Depends on outputs from [`eks-cluster`](../eks-cluster/) and calls [`iam-irsa`](../iam-irsa/) internally when `runner_irsa_policy_json` is set.

## Registering runners (one-time, manual — GitHub App credentials are secrets)

1. [Create a GitHub App](https://docs.github.com/en/apps/creating-github-apps) on the org (or a repo) with the runner-registration permissions ARC needs, generate a private key, and note the App ID and Installation ID.
2. Populate the placeholder secret this module created:
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id "$(terragrunt output -raw github_app_secret_name)" \
     --secret-string "$(jq -n --arg id "$APP_ID" --arg inst "$INSTALLATION_ID" --arg key "$(cat private-key.pem)" \
       '{github_app_id: $id, github_app_installation_id: $inst, github_app_private_key: $key}')"
   ```
3. Sync it into the Kubernetes secret the scale set expects (no External Secrets Operator yet — see "Not yet built" below):
   ```bash
   aws secretsmanager get-secret-value --secret-id "$(terragrunt output -raw github_app_secret_name)" \
     --query SecretString --output text | \
   jq -r 'to_entries[] | "--from-literal=\(.key)=\(.value)"' | \
   xargs kubectl create secret generic arc-github-app -n arc-runners
   ```
4. Install the runner scale set — see [`kubernetes/eks/arc/README.md`](../../../kubernetes/eks/arc/README.md).

## Example

```hcl
module "arc" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/arc?ref=modules/arc/v1.0.0"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # Optional: let runner pods push to ECR without static credentials.
  runner_irsa_policy_json = data.aws_iam_policy_document.runner_ecr_push.json
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
| `runner_irsa_policy_json` | Inline policy for runner pods' AWS access; `null` skips the role | `string` | `null` |
| `runner_service_account_name` | Service account the IRSA role trusts | `string` | `"arc-runner"` |
| `tags` | Extra tags on IAM/Secrets Manager resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `github_app_secret_arn` / `github_app_secret_name` | The placeholder secret — populate out of band |
| `runner_irsa_role_arn` | Runner pods' IRSA role ARN, or `null` |
| `controller_namespace` / `runners_namespace` | For wiring the Phase 2 scale-set Helm install |

**Not yet built:** an External Secrets Operator sync from Secrets Manager straight into the runner namespace (today's flow is the manual `kubectl create secret` above). Worth adding once a second AWS-backed secret shows up elsewhere in the fleet and the sync logic is worth sharing.
