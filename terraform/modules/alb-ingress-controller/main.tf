# The AWS Load Balancer Controller's IAM policy is long (~20 statements)
# and AWS revises it as ALB/NLB features are added. Rather than transcribe
# and risk a stale/incomplete copy — which fails silently as per-action
# AccessDenied at runtime, not at apply time — fetch the exact policy
# published for the pinned controller_app_version directly from upstream.
data "http" "controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.controller_app_version}/docs/install/iam_policy.json"

  request_headers = {
    Accept = "application/json"
  }
}

resource "aws_iam_policy" "controller" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  description = "Upstream policy for aws-load-balancer-controller ${var.controller_app_version}, fetched from kubernetes-sigs/aws-load-balancer-controller at apply time."
  policy      = data.http.controller_iam_policy.response_body

  tags = var.tags
}

module "controller_irsa" {
  source = "../iam-irsa"

  role_name            = "${var.cluster_name}-aws-load-balancer-controller"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = var.namespace
  service_account_name = "aws-load-balancer-controller"
  policy_arns          = [aws_iam_policy.controller.arn]
  tags                 = var.tags
}

resource "helm_release" "controller" {
  name       = "aws-load-balancer-controller"
  namespace  = var.namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.controller_helm_version

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.aws_region
      vpcId       = var.vpc_id
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.controller_irsa.role_arn
        }
      }
    })
  ]
}
