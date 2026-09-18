# Hybrid Fleet DevOps Platform

A single control plane that gives cloud-native (EKS) and self-managed VM-based Kubernetes clusters shared identity, shared CI/CD tooling, shared policy, and shared observability — without forcing the VM tier to become cloud-native.

This repo simulates a real-world hybrid fleet: EKS + Karpenter for cloud-native workloads, and a self-managed `kubeadm` cluster on persistent EC2 Auto Scaling Groups standing in for on-prem VM-based Kubernetes (e.g. Nutanix NKP) — see [`docs/decision-stack.md`](docs/decision-stack.md) for why kubeadm over k3s or a managed alternative. Both tiers share Terraform modules, GitHub Actions self-hosted runners, OPA/Gatekeeper policy, and a federated observability plane.

Full design rationale, the six-layer decision stack, and failure-mode pitfalls live in [`docs/`](docs/).

## Repo Layout

```
terraform/
  modules/          # Shared, versioned Terraform modules (the "private registry")
  live/              # Terragrunt live environments that consume the modules
    global/          # Account-level bootstrap (Terraform state backend)
    dev/             # Per-environment stacks (cloud VPC, EKS, Karpenter, ARC, on-prem VPC, VM-tier K8s, Nexus, VPN, observability)
ansible/             # Config management for the VM tier: kubeadm bootstrap (over SSM, no SSH), Nexus setup
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
- [x] **Phase 1 — Cloud-native tier.** EKS cluster + core system node group + IRSA (generic module), Karpenter controller (IAM, Spot-interruption SQS/EventBridge, Helm release) and its default NodePool/EC2NodeClass.
- [x] **Phase 2 — Self-hosted CI.** GitHub Actions Runner Controller (ARC) on EKS, GitHub App credentials in Secrets Manager, optional runner-pod IRSA, ephemeral autoscaled runner pods on a Spot-first CI-only Karpenter NodePool.
- [x] **Phase 3 — VM tier.** "On-prem" VPC, persistent EC2 ASGs (control-plane + worker node groups), SSM-only IAM (no SSH), kubeadm bootstrap + Calico CNI via Ansible over the SSM connection plugin.
- [ ] **Phase 4 — Hybrid networking.** Site-to-Site VPN linking the cloud and on-prem VPCs, Route 53 private hosted zone, ALB Ingress Controller.
- [ ] **Phase 5 — Shared module registry discipline.** Semantic-versioned module tags, Terragrunt `_envcommon` patterns, module consumption from both tiers.
- [ ] **Phase 6 — Nexus Sonatype.** Dedicated EC2 instance (not containerized), EBS storage, S3 lifecycle-managed backup/restore runbook.
- [ ] **Phase 7 — Policy parity.** OPA/Gatekeeper deployed identically on both clusters.
- [ ] **Phase 8 — Federated observability.** Amazon Managed Prometheus + Grafana, OpenTelemetry Collector on both tiers, CloudWatch, Alertmanager → PagerDuty/OpsGenie.
- [ ] **Phase 9 — Runbooks & on-call discipline.** Versioned in-repo runbooks, cost allocation tags per team.

## Getting Started

Prerequisites: an AWS account, Terraform >= 1.7, Terragrunt >= 0.58, `kubectl`, `helm`, `ansible`, an SSM-enabled AWS CLI profile.

```bash
# 1. Bootstrap remote state (one-time, per AWS account)
cd terraform/live/global/state-backend
terraform init && terraform apply

# 2. Deploy the cloud tier, in order (each stack reads the previous one's
#    outputs via a Terragrunt `dependency` block)
cd terraform/live/dev/cloud-vpc  && terragrunt init && terragrunt apply
cd ../eks                        && terragrunt init && terragrunt apply
cd ../karpenter                  && terragrunt init && terragrunt apply
cd ../arc                        && terragrunt init && terragrunt apply

# 3. Apply the kubectl-managed cluster-native resources (Karpenter
#    NodePools/EC2NodeClass, and — after registering runners, see
#    terraform/modules/arc/README.md — the ARC runner scale set)
aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1
kubectl apply -f kubernetes/eks/karpenter/

# 4. Deploy the VM tier, then bootstrap kubeadm on it over SSM (no SSH) —
#    see ansible/README.md for the full Ansible wiring steps
cd ../../onprem-vpc && terragrunt init && terragrunt apply
cd ../vm-k8s         && terragrunt init && terragrunt apply
```

See [`docs/architecture.md`](docs/architecture.md) for the full system diagram and [`docs/runbooks/`](docs/runbooks/) for operational procedures.

## License

See [`LICENSE`](LICENSE).
