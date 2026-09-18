# Hybrid Fleet DevOps Platform

A single control plane that gives cloud-native (EKS) and self-managed VM-based Kubernetes clusters shared identity, shared CI/CD tooling, shared policy, and shared observability — without forcing the VM tier to become cloud-native.

This repo simulates a real-world hybrid fleet: EKS + Karpenter for cloud-native workloads, and a self-managed `kubeadm` cluster on persistent EC2 Auto Scaling Groups standing in for on-prem VM-based Kubernetes (e.g. Nutanix NKP) — see [`docs/decision-stack.md`](docs/decision-stack.md) for why kubeadm over k3s or a managed alternative. Both tiers share Terraform modules, GitHub Actions self-hosted runners, OPA/Gatekeeper policy, and a federated observability plane.

Full design rationale, the six-layer decision stack, and failure-mode pitfalls live in [`docs/`](docs/).

## Repo Layout

```
terraform/
  modules/          # Shared, git-tag-versioned Terraform modules (the "private registry") — see docs/architecture.md
  _envcommon/       # Shared Terragrunt config fragments (currently: the EKS-controller helm-provider pattern)
  live/              # Terragrunt live environments that consume the modules, by tag
    global/          # Account-level bootstrap (Terraform state backend)
    dev/             # Per-environment stacks (cloud VPC, EKS, Karpenter, ARC, ALB Ingress, OPA/Gatekeeper, OTel Collector, on-prem VPC, VM-tier K8s, VPN, DNS, Nexus, observability)
ansible/             # Config management for the VM tier: kubeadm bootstrap, Gatekeeper, OTel Collector, Nexus (all over SSM, no SSH)
kubernetes/
  base/              # Manifests applied identically to BOTH clusters (OPA/Gatekeeper, OTel Collector)
  eks/               # EKS-only workloads (ARC runner controller, Karpenter NodePools, example ALB Ingress)
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
- [x] **Phase 4 — Hybrid networking.** Real Site-to-Site VPN (VGW + self-managed strongSwan customer gateway, configured via Ansible over SSM) linking the cloud and on-prem VPCs, a Route 53 private hosted zone associated with both, and the AWS Load Balancer Controller for ALB Ingress on EKS.
- [x] **Phase 5 — Shared module registry discipline.** All 13 modules git-tagged `modules/<name>/v1.0.0`; every live stack (both tiers) consumes its module through that tag, not a local path — `cloud-vpc` and `onprem-vpc` both pull the identical `modules/vpc/v1.0.0`. The five EKS-controller stacks' duplicated `helm` provider boilerplate now lives once, in a Terragrunt `_envcommon` include.
- [x] **Phase 6 — Nexus Sonatype.** Dedicated EC2 instance (not containerized), standalone EBS data volume that outlives instance replacement, S3 lifecycle-managed daily backups, and a full [restore runbook](docs/runbooks/nexus-backup-restore.md).
- [x] **Phase 7 — Policy parity.** OPA/Gatekeeper controller on both clusters (Terraform+Helm on EKS, Ansible+Helm on the VM tier — same chart version/config, different invocation), with the same `ConstraintTemplate`/`Constraint` YAML `kubectl`-applied identically to both.
- [x] **Phase 8 — Federated observability.** Amazon Managed Prometheus (+ its managed Alertmanager) and Amazon Managed Grafana, an OpenTelemetry Collector on both tiers sharing one literal pipeline-config file, and CloudWatch alarms (EC2 status checks, VPN tunnel state) routed to PagerDuty/OpsGenie via SNS in parallel to Prometheus-evaluated alerts.
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

cd ../opa-gatekeeper              && terragrunt init && terragrunt apply
cd ../observability               && terragrunt init && terragrunt apply
cd ../otel-collector               && terragrunt init && terragrunt apply

# 3. Apply the kubectl-managed cluster-native resources (Karpenter
#    NodePools/EC2NodeClass, the OPA/Gatekeeper policy content, and —
#    after registering runners, see terraform/modules/arc/README.md — the
#    ARC runner scale set)
aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1
kubectl apply -f kubernetes/eks/karpenter/
kubectl apply -f kubernetes/base/opa-gatekeeper/ -f policy/gatekeeper-constraints/

# 4. Deploy the VM tier, then bootstrap kubeadm + Gatekeeper + the OTel
#    Collector on it over SSM (no SSH) — see ansible/README.md for the
#    full Ansible wiring steps. vm-k8s depends on ../observability (for
#    its AMP remote-write IAM grant) even though that stack is applied
#    later in this list — Terragrunt orders by the dependency graph, not
#    by this list's order, so re-apply vm-k8s once ../observability exists.
cd ../../onprem-vpc && terragrunt init && terragrunt apply
cd ../vm-k8s         && terragrunt init && terragrunt apply
# (ansible-playbook playbooks/bootstrap-k8s.yml && playbooks/configure-policy.yml
#  && playbooks/configure-observability.yml, then kubectl apply -f
#  kubernetes/base/opa-gatekeeper/ -f policy/gatekeeper-constraints/ against
#  the VM-tier kubeconfig too, to actually complete policy parity)

# 5. Hybrid networking: DNS, ALB Ingress, and the Site-to-Site VPN linking
#    the two VPCs (then configure strongSwan — see ansible/README.md)
cd ../dns                     && terragrunt init && terragrunt apply
cd ../alb-ingress-controller  && terragrunt init && terragrunt apply
cd ../vpn                     && terragrunt init && terragrunt apply

# 6. Nexus (depends on ../dns for its internal DNS record), then install it
#    — see ansible/README.md for the full Ansible wiring steps
cd ../nexus && terragrunt init && terragrunt apply
```

See [`docs/architecture.md`](docs/architecture.md) for the full system diagram and [`docs/runbooks/`](docs/runbooks/) for operational procedures.

## License

See [`LICENSE`](LICENSE).
