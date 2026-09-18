# Interview Talking Points

- **Why the VM tier uses kubeadm/k3s instead of EKS Anywhere or a managed alternative:** it deliberately reproduces the real operational burden (you own upgrades, the CNI, the control plane) rather than abstracting it away — the same skill a hybrid-fleet role screens for.
- **Why Nexus lives on a VM, not in a container on EKS:** matches the real target environment and demonstrates comfort operating stateful infra outside of Kubernetes, including backup/restore discipline.
- **Why ARC runners are ephemeral rather than a static pool:** security (no persistent lateral-movement surface) and cost (no idle capacity) — a single decision that improves both.
- **Why OpenTelemetry over a single vendor agent:** keeps the observability backend swappable, directly answering the "familiarity with Datadog/Grafana/OTel/ELK" ask as interchangeable rather than a single bet.
- **Cost-allocation tagging per team:** an extension of a finance/accounting background — chargeback and auditability translate directly into platform engineering discipline.
- **Why EKS and Karpenter are separate Terragrunt stacks, not one:** avoids the classic "Helm/Kubernetes provider configured from a resource created in the same apply" chicken-and-egg problem — see [`docs/architecture.md`](architecture.md#why-eks-and-karpenter-are-separate-terragrunt-stacks). A small detail that signals real hands-on Terraform experience rather than copy-pasted examples.

## Internal Reuse Notes

- Reuses the EKS + Karpenter pattern already established elsewhere — no need to re-justify that choice from scratch in this project.
- The Terraform module registry and Terragrunt pattern is a natural precursor to a companion Terragrunt/CI-CD-focused project — this repo can absorb that scope rather than duplicating it later.
- OPA/Gatekeeper usage here is consistent with a policy-as-code approach used in a developer-platform-focused project; the two can cross-reference each other as the same governance philosophy applied at different layers (developer platform vs. hybrid fleet).
