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

- `values-runner-scale-set.example.yaml` — starting point per team: `githubConfigUrl`, min/max runners, the `nodeSelector`/`tolerations` that pin runner pods to the CI-only Karpenter NodePool (Spot-first, tainted so runner scaling never starves app workloads — see [`docs/pitfalls.md`](../../../docs/pitfalls.md)), and explicit `resources` on both `listenerTemplate` and `template`'s containers.

Each team's actual `values-*.yaml` (with their real `githubConfigUrl`) isn't checked in here (see `.gitignore`) — copy the example per team/repo as shown above.

## Every Pod here needs `resources`, including the controller's own listener

A real `helm install` with the chart's own defaults was rejected outright by the cluster's `require-container-limits` Gatekeeper constraint ([`policy/gatekeeper-constraints/`](../../../policy/gatekeeper-constraints/)):

```
admission webhook "validation.gatekeeper.sh" denied the request:
[require-container-limits] Container <listener> has no CPU limit set
[require-container-limits] Container <listener> has no memory limit set
```

That constraint applies to every real `Pod` cluster-wide (`kube-system`/`gatekeeper-system`/etc. excluded, nothing ARC-specific) — the listener pod the controller creates per scale set is not exempt, and neither is the ephemeral runner pod spawned per job. Both need explicit `resources` in the values file: `listenerTemplate.spec.containers[]` (container name must be exactly `listener` — anything else is treated as an unrelated sidecar and its resources won't apply) and `template.spec.containers[]` for the runner. Both are already set in `values-runner-scale-set.example.yaml`; if you strip them out while customizing, expect the same rejection.

Verified for real: with both fixed, the listener pod reached `1/1 Running` and its logs showed a real GitHub App token exchange succeeding (`getting access token for GitHub App auth` → `getting runner registration token` → `getting Actions tenant URL and JWT`), then settled into steady-state long-polling for jobs.
