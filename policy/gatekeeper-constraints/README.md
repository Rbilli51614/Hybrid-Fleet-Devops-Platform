# policy/gatekeeper-constraints

`Constraint` instances — which of the `ConstraintTemplate`s in [`kubernetes/base/opa-gatekeeper/`](../../kubernetes/base/opa-gatekeeper/) are actually turned on, against which resource kinds, with what parameters. Applied identically to both clusters alongside the templates — see that directory's README for the apply command and how these were verified (`opa check`/`opa eval` against the underlying Rego, since there's no live cluster in this repo to admission-test against).

All four exclude `kube-system`, `kube-node-lease`, `kube-public`, and `gatekeeper-system` — enforcing these against cluster system components (CoreDNS, CNI, kube-proxy, Gatekeeper's own pods) would break cluster bootstrap, not just this repo's demo workloads.

## Files

- `require-team-label.yaml` — every `Deployment` needs a `team` label. Ties directly to [`docs/decision-stack.md`](../../docs/decision-stack.md)'s Cost layer: per-team cost allocation tagging needs the label to exist before it can mean anything. The AWS-side half of that story — activating cost allocation tags, and the account-level bridge that imports these K8s labels into Cost Explorer/CUR — is [`terraform/modules/cost-allocation-tags`](../../terraform/modules/cost-allocation-tags/).
- `require-container-limits.yaml` — every `Pod`'s containers need CPU and memory limits set.
- `disallow-latest-tag.yaml` — blocks images ending in `:latest`.
- `block-privileged-containers.yaml` — blocks `securityContext.privileged: true`.
