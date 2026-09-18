data "aws_iam_policy_document" "remote_write" {
  statement {
    actions   = ["aps:RemoteWrite"]
    resources = [var.amp_workspace_arn]
  }
}

module "controller_irsa" {
  source = "../iam-irsa"

  role_name            = "${var.cluster_name}-otel-collector"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = var.namespace
  service_account_name = "otel-collector"
  inline_policy_json   = data.aws_iam_policy_document.remote_write.json
  tags                 = var.tags
}

resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.otel_collector_helm_version

  values = [
    templatefile("${path.module}/../../../kubernetes/base/otel-collector/values.yaml.tmpl", {
      amp_remote_write_url = var.amp_remote_write_url
      aws_region           = var.aws_region
    }),
    yamlencode({
      serviceAccount = {
        create = true
        name   = "otel-collector"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.controller_irsa.role_arn
        }
      }
    }),
  ]
}
