locals {
  github_app_secret_name = coalesce(var.github_app_secret_name, "${var.cluster_name}-arc-github-app")
}

# ---------------------------------------------------------------------------
# GitHub App credentials container
#
# Terraform provisions the Secrets Manager secret so it's covered by the
# same IaC/audit trail as everything else, but deliberately does not manage
# its real content: app ID, installation ID, and private key are populated
# out of band (see README) and the lifecycle rule stops a subsequent
# `terraform apply` from ever overwriting them with the placeholder again.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "github_app" {
  name        = local.github_app_secret_name
  description = "GitHub App credentials (app ID, installation ID, private key) used to register ARC self-hosted runners for ${var.cluster_name}."

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "github_app_placeholder" {
  secret_id = aws_secretsmanager_secret.github_app.id

  secret_string = jsonencode({
    github_app_id              = "REPLACE_ME"
    github_app_installation_id = "REPLACE_ME"
    github_app_private_key     = "REPLACE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ---------------------------------------------------------------------------
# Runner workload identity
#
# Optional: grants the runner pods' own service account AWS permissions for
# what CI jobs actually need to do (push to ECR, read a build-artifact
# bucket, etc.) via IRSA instead of long-lived keys baked into the runner
# image or job env. Scope runner_irsa_policy_json per team; leave
# attach_runner_irsa_policy at its default (false) for runners that only
# need GitHub access.
# ---------------------------------------------------------------------------

module "runner_irsa" {
  count  = var.attach_runner_irsa_policy ? 1 : 0
  source = "../iam-irsa"

  role_name            = "${var.cluster_name}-arc-runner"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = var.runners_namespace
  service_account_name = var.runner_service_account_name
  attach_inline_policy = true
  inline_policy_json   = var.runner_irsa_policy_json
  tags                 = var.tags
}

# ---------------------------------------------------------------------------
# Controller install
#
# Only the controller is Terraform-managed. The per-repo/org runner scale
# set (gha-runner-scale-set) is deliberately left to kubectl/helm outside
# Terraform — see kubernetes/eks/arc/ — because which repos get runners,
# and at what scale, is a per-team config decision, not cloud infra.
# ---------------------------------------------------------------------------

resource "helm_release" "arc_controller" {
  name             = "arc"
  namespace        = var.controller_namespace
  create_namespace = true

  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = var.controller_helm_version
}
