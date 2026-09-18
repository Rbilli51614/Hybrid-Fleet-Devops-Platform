# kubernetes/eks/ingress

Example `Ingress` manifests for the AWS Load Balancer Controller (installed by [`terraform/modules/alb-ingress-controller`](../../../terraform/modules/alb-ingress-controller/)). No actual application workloads live in this repo yet, so nothing here is applied by default — `example-ingress.yaml` exists to show the annotation shape a team would copy for their own service, same Terraform/kubectl split as [Karpenter's NodePool](../karpenter/) and [ARC's runner scale set](../arc/).

Points at `example-app.hybrid-fleet.internal` — a name under the private hosted zone [`terraform/modules/private-dns`](../../../terraform/modules/private-dns/) creates. Add a matching `A`/`ALIAS` record pointing at the ALB once a real service exists.
