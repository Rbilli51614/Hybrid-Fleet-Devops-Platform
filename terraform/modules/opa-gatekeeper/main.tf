# Deliberately the only module in this repo with no cloud resources at
# all: Gatekeeper is a pure in-cluster admission webhook, no AWS API calls,
# no IAM. Still Terraform-managed on the EKS side (rather than kubectl'd
# like the NodePool/RunnerScaleSet/Ingress examples) because controller
# *installation* is a platform-infra concern in this repo's split, same
# tier as Karpenter/ARC/the ALB controller — see
# docs/architecture.md#the-terraform-kubectl-boundary-for-cluster-native-resources.
# The policy *content* (ConstraintTemplates, Constraints) stays kubectl-
# applied, under kubernetes/base/opa-gatekeeper/ and policy/
# gatekeeper-constraints/, identically on both clusters.

resource "helm_release" "gatekeeper" {
  name             = "gatekeeper"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart      = "gatekeeper"
  version    = var.gatekeeper_helm_version

  values = [
    yamlencode({
      replicas = var.replicas
      audit = {
        auditInterval = var.audit_interval_seconds
      }
    })
  ]
}
