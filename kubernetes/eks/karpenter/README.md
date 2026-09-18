# kubernetes/eks/karpenter

`NodePool` and `EC2NodeClass` custom resources. Deliberately kept as plain manifests applied via `kubectl` rather than Terraform-managed (`kubernetes_manifest`/`kubectl_manifest`) — the [`karpenter` Terraform module](../../../terraform/modules/karpenter/) owns the controller install and its IAM/SQS plumbing; these cluster-native resources are the natural boundary for a GitOps tool (ArgoCD/Flux) to take over later without touching Terraform state.

## Apply

```bash
aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1
kubectl apply -f ec2nodeclass-default.yaml -f nodepool-default.yaml -f nodepool-ci-runners.yaml
```

## Files

- `ec2nodeclass-default.yaml` — AMI family, node IAM role, and subnet/security-group discovery (by the `karpenter.sh/discovery` tag set in the `vpc` and `eks-cluster` Terraform modules).
- `nodepool-default.yaml` — general application workload pool: diversified instance families/generations, spot+on-demand mix, empty-node consolidation. See [`docs/pitfalls.md`](../../../docs/pitfalls.md) for why instance diversification matters here.
- `nodepool-ci-runners.yaml` — Spot-first, tainted `workload=ci-runner:NoSchedule` pool for ARC runner pods (see [`kubernetes/eks/arc/`](../arc/)), so CI scaling never starves app workload capacity — see [`docs/pitfalls.md`](../../../docs/pitfalls.md).

**If you rename the cluster:** update `role` in `ec2nodeclass-default.yaml` to match the `karpenter` module's `node_iam_role_name` output (`<cluster_name>-karpenter-node`), and both `karpenter.sh/discovery` tag values to the new cluster name.
