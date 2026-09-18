# Hybrid Fleet DevOps Platform

A single control plane that gives cloud-native (EKS) and self-managed VM-based Kubernetes clusters shared identity, shared CI/CD tooling, shared policy, and shared observability — without forcing the VM tier to become cloud-native.

This repo simulates a real-world hybrid fleet: EKS + Karpenter for cloud-native workloads, and a self-managed `kubeadm`/`k3s` cluster on a persistent EC2 Auto Scaling Group standing in for on-prem VM-based Kubernetes (e.g. Nutanix NKP). Both tiers share Terraform modules, GitHub Actions self-hosted runners, OPA/Gatekeeper policy, and a federated observability plane.

Full design rationale, the six-layer decision stack, and failure-mode pitfalls live in [`docs/`](docs/).

## Repo Layout

```
terraform/
  modules/          # Shared, versioned Terraform modules (the "private registry")
  live/              # Terragrunt live environments that consume the modules
    global/          # Account-level bootstrap (Terraform state backend)
    dev/             # Per-environment stacks (cloud VPC, EKS, on-prem VPC, VM-tier K8s, Nexus, VPN, observability)
ansible/             # Config management for the VM tier: kubeadm/k3s bootstrap, Nexus setup
kubernetes/
  base/              # Manifests applied identically to BOTH clusters (OPA/Gatekeeper, OTel Collector)
  eks/               # EKS-only workloads (ARC runner controller, Karpenter NodePools)
  vm-tier/           # VM-cluster-only manifests
policy/              # Gatekeeper constraint templates and constraints
.github/workflows/   # CI/CD: Terraform plan/apply, reusable workflow components
docs/                # Architecture, decision stack, pitfalls, runbooks, interview talking points
```

## Build Roadmap

This is being built in phases, each independently demonstrable:

- [x] **Phase 0 — Repo scaffolding & Terraform foundation.** Directory structure, remote state backend (S3 + DynamoDB), shared VPC module, Terragrunt root config, CI skeleton.
- [ ] **Phase 1 — Cloud-native tier.** EKS cluster + Karpenter NodePools, IRSA, ALB Ingress.
- [ ] **Phase 2 — Self-hosted CI.** GitHub Actions Runner Controller (ARC) on EKS, registered against a GitHub App, ephemeral autoscaled runner pods.
- [ ] **Phase 3 — VM tier.** Persistent EC2 ASG, `kubeadm`/`k3s` bootstrap via Ansible, SSM-only access (no SSH).
- [ ] **Phase 4 — Hybrid networking.** "On-prem" VPC + Site-to-Site VPN linking the two tiers, Route 53 private hosted zone.
- [ ] **Phase 5 — Shared module registry discipline.** Semantic-versioned module tags, Terragrunt `_envcommon` patterns, module consumption from both tiers.
- [ ] **Phase 6 — Nexus Sonatype.** Dedicated EC2 instance (not containerized), EBS storage, S3 lifecycle-managed backup/restore runbook.
- [ ] **Phase 7 — Policy parity.** OPA/Gatekeeper deployed identically on both clusters.
- [ ] **Phase 8 — Federated observability.** Amazon Managed Prometheus + Grafana, OpenTelemetry Collector on both tiers, CloudWatch, Alertmanager → PagerDuty/OpsGenie.
- [ ] **Phase 9 — Runbooks & on-call discipline.** Versioned in-repo runbooks, cost allocation tags per team.

## Getting Started

Prerequisites: an AWS account, Terraform >= 1.7, Terragrunt >= 0.58, `kubectl`, `helm`, an SSM-enabled AWS CLI profile.

```bash
# 1. Bootstrap remote state (one-time, per AWS account)
cd terraform/live/global/state-backend
terraform init && terraform apply

# 2. Deploy an environment stack via Terragrunt
cd terraform/live/dev/cloud-vpc
terragrunt init && terragrunt plan
```

See [`docs/architecture.md`](docs/architecture.md) for the full system diagram and [`docs/runbooks/`](docs/runbooks/) for operational procedures.

## License

See [`LICENSE`](LICENSE).
