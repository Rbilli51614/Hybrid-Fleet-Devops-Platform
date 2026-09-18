# vm-tier

Manifests specific to the VM-tier cluster only — deliberately empty. Every controller this repo installs on the VM tier (`opa-gatekeeper`, `otel-collector`) is an Ansible role, not a raw manifest here (see [`ansible/README.md`](../../ansible/README.md)), and every workload-level resource (`ConstraintTemplate`s, `Constraint`s) is `kubectl`-applied identically to both clusters from [`kubernetes/base/`](../base/), not tier-specific. Nothing this repo built ever needed a VM-tier-only manifest; this directory stays as the place one would go if that changes.
