# kubernetes/eks/arc

The per-repo/org GitHub Actions runner scale set. The controller itself is Terraform-managed (see [`terraform/modules/arc`](../../../terraform/modules/arc/)); the scale set is deliberately left as a `helm install` here, same Terraform/kubectl split used for [Karpenter's NodePool](../../../kubernetes/eks/karpenter/) — which repos get runners, and at what scale, is a per-team decision, not cloud infra.

## Apply

Prerequisite: the GitHub App secret has been created and synced into a Kubernetes secret — see [`terraform/modules/arc/README.md`](../../../terraform/modules/arc/README.md#registering-runners-one-time-manual--github-app-credentials-are-secrets).

```bash
aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1

cp values-runner-scale-set.example.yaml values-runner-scale-set.myteam.yaml
# edit githubConfigUrl (and the release name below) for your repo/org

helm install myteam-runners \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.9.3 \
  --namespace arc-runners \
  -f values-runner-scale-set.myteam.yaml
```

## Files

- `values-runner-scale-set.example.yaml` — starting point per team: `githubConfigUrl`, min/max runners, and the `nodeSelector`/`tolerations` that pin runner pods to the CI-only Karpenter NodePool (Spot-first, tainted so runner scaling never starves app workloads — see [`docs/pitfalls.md`](../../../docs/pitfalls.md)).

Each team's actual `values-*.yaml` (with their real `githubConfigUrl`) isn't checked in here — copy the example per team/repo as shown above.
