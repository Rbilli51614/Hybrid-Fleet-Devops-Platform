# kubernetes/base/opa-gatekeeper

`ConstraintTemplate`s — the Rego policy definitions Gatekeeper enforces. Applied with the exact same `kubectl apply -f` command against **both** clusters, which is what makes "policy parity" in this repo a literal claim rather than a diagram label: same files, same command, twice. The actual `Constraint` instances (which templates are turned on, and with what parameters) live in [`policy/gatekeeper-constraints/`](../../../policy/gatekeeper-constraints/) — template definition and instantiation are kept separate on purpose, so a template can be reused by different constraints per environment later without duplicating Rego.

The controller itself is installed separately per tier — [`terraform/modules/opa-gatekeeper`](../../../terraform/modules/opa-gatekeeper/) on EKS, [`ansible/roles/opa-gatekeeper`](../../../ansible/roles/opa-gatekeeper/) on the VM tier — same chart version and values on both, different invocation mechanism because that's how every controller in this repo is split. See [`docs/architecture.md`](../../../docs/architecture.md) for the reasoning.

## Apply (to each cluster)

```bash
# EKS
aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1
kubectl apply -f kubernetes/base/opa-gatekeeper/ -f policy/gatekeeper-constraints/

# VM tier — kubeconfig is on the control-plane instance
# (~/.kube/config, set up by ansible/roles/k8s-control-plane); run kubectl
# there over SSM, or copy the kubeconfig out via
# `aws ssm start-session` + a file-transfer plugin, or a proxy.
kubectl --kubeconfig <vm-tier kubeconfig> apply -f kubernetes/base/opa-gatekeeper/ -f policy/gatekeeper-constraints/
```

## Files

- `constrainttemplate-required-labels.yaml` — `K8sRequiredLabels`, the standard Gatekeeper library template for enforcing arbitrary required label keys (optionally with a regex).
- `constrainttemplate-container-limits.yaml` — `K8sContainerLimits`, requires every container set CPU and memory limits.
- `constrainttemplate-disallowed-tags.yaml` — `K8sDisallowedTags`, blocks container images whose tag matches any of a configured disallowed list (e.g. `:latest`).
- `constrainttemplate-block-privileged.yaml` — `K8sBlockPrivileged`, blocks containers with `securityContext.privileged: true`.

## How these were verified

`terraform validate` doesn't reach into Rego, and there's no live cluster in this repo to admission-test against — so each template's Rego was extracted and checked directly with the `opa` CLI: `opa check --v0-compatible` for syntax (Gatekeeper 3.17.1 bundles a pre-OPA-v1 engine, which doesn't require the `if`/`contains` keywords OPA's own CLI defaults to since v1.0 — `--v0-compatible` matches what Gatekeeper actually runs), and `opa eval` against both a violating and a passing sample input per template to confirm the actual logic, not just the syntax, does what it claims.
