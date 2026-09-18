# kubernetes/eks/karpenter

`NodePool` and `EC2NodeClass` custom resources. Deliberately kept as plain manifests applied via `kubectl` rather than Terraform-managed (`kubernetes_manifest`/`kubectl_manifest`) — the [`karpenter` Terraform module](../../../terraform/modules/karpenter/) owns the controller install and its IAM/SQS plumbing; these cluster-native resources are the natural boundary for a GitOps tool (ArgoCD/Flux) to take over later without touching Terraform state.

## Apply

```bash
aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1
kubectl apply -f ec2nodeclass-default.yaml -f nodepool-default.yaml
```

## Files

- `ec2nodeclass-default.yaml` — AMI family, node IAM role, and subnet/security-group discovery (by the `karpenter.sh/discovery` tag set in the `vpc` and `eks-cluster` Terraform modules).
- `nodepool-default.yaml` — general application workload pool: diversified instance families/generations, spot+on-demand mix, empty-node consolidation. See [`docs/pitfalls.md`](../../../docs/pitfalls.md) for why instance diversification matters here.

A second, CI-runner-specific NodePool (Spot-first, tainted so ARC runner pods never contend with app workloads for capacity) is added in Phase 2 alongside the ARC runner controller — see [`docs/pitfalls.md`](../../../docs/pitfalls.md).

**If you rename the cluster:** update `role` in `ec2nodeclass-default.yaml` to match the `karpenter` module's `node_iam_role_name` output (`<cluster_name>-karpenter-node`), and both `karpenter.sh/discovery` tag values to the new cluster name.
