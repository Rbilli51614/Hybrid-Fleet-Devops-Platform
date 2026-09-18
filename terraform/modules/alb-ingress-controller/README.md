# alb-ingress-controller

Installs the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) via Helm — the controller that turns Kubernetes `Ingress`/`Service` (type `LoadBalancer`) resources into real ALBs/NLBs. `Ingress` resources for actual workloads are deliberately **not** managed here, same Terraform/kubectl split as [Karpenter's NodePool](../../../kubernetes/eks/karpenter/) and [ARC's runner scale set](../../../kubernetes/eks/arc/) — see an example at [`kubernetes/eks/ingress/`](../../../kubernetes/eks/ingress/).

Versioned via git tags (`modules/alb-ingress-controller/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Where the IAM policy comes from

The controller's IAM policy is long, AWS revises it as ALB/NLB features ship, and hand-transcribing ~20 statements risks a stale or subtly wrong copy — the kind of bug that fails silently as a runtime `AccessDenied` on one specific action, not as a Terraform error. Instead of committing a copy, `main.tf` fetches the exact policy published for the pinned `controller_app_version` directly from `kubernetes-sigs/aws-load-balancer-controller` at apply time via the `http` provider. Bump `controller_app_version` and `controller_helm_version` together — the chart and controller app versions aren't independently numbered (chart `1.8.1` ships controller app `v2.8.1`); check the [releases page](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases) before bumping either.

## Example

```hcl
module "alb_ingress_controller" {
  source = "git::https://github.com/<org>/Hybrid-Fleet-Devops-Platform.git//terraform/modules/alb-ingress-controller?ref=modules/alb-ingress-controller/v1.0.0"

  cluster_name      = module.eks.cluster_name
  vpc_id            = module.cloud_vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name | `string` | — |
| `vpc_id` | VPC the cluster (and ALBs/NLBs) live in | `string` | — |
| `oidc_provider_arn` / `oidc_provider_url` | Cluster IRSA trust anchor | `string` | — |
| `aws_region` | Region the cluster runs in | `string` | `"us-east-1"` |
| `namespace` | Namespace for the controller | `string` | `"kube-system"` |
| `controller_helm_version` | Helm chart version | `string` | `"1.8.1"` |
| `controller_app_version` | Controller git tag whose IAM policy is fetched | `string` | `"v2.8.1"` |
| `tags` | Extra tags on IAM resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `controller_role_arn` | Controller's IRSA role ARN |
| `iam_policy_arn` | ARN of the fetched-at-apply-time upstream policy |
