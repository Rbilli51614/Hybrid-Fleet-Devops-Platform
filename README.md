# Hybrid Fleet DevOps Platform

A single control plane that gives cloud-native (EKS) and self-managed VM-based Kubernetes clusters shared identity, shared CI/CD tooling, shared policy, and shared observability — without forcing the VM tier to become cloud-native.

This repo simulates a real-world hybrid fleet: EKS + Karpenter for cloud-native workloads, and a self-managed `kubeadm` cluster on persistent EC2 Auto Scaling Groups standing in for on-prem VM-based Kubernetes (e.g. Nutanix NKP) — see [`docs/decision-stack.md`](docs/decision-stack.md) for why kubeadm over k3s or a managed alternative. Both tiers share Terraform modules, GitHub Actions self-hosted runners, OPA/Gatekeeper policy, and a federated observability plane.

Full design rationale, the six-layer decision stack, and failure-mode pitfalls live in [`docs/`](docs/). For a plain-language summary of what this project is and the real issues found and fixed along the way, see [`docs/executive-summary.md`](docs/executive-summary.md).

## Repo Layout

```
terraform/
  modules/          # Shared, git-tag-versioned Terraform modules (the "private registry") — see docs/architecture.md
  _envcommon/       # Shared Terragrunt config fragments (currently: the EKS-controller helm-provider pattern)
  live/              # Terragrunt live environments that consume the modules, by tag
    global/          # Account-level bootstrap (Terraform state backend, cost allocation tag activation)
    dev/             # Per-environment stacks (cloud VPC, EKS, Karpenter, ARC, ALB Ingress, OPA/Gatekeeper, OTel Collector, on-prem VPC, VM-tier K8s, VPN, DNS, Nexus, observability)
ansible/             # Config management for the VM tier: kubeadm bootstrap, Gatekeeper, OTel Collector, Nexus (all over SSM, no SSH)
kubernetes/
  base/              # Manifests applied identically to BOTH clusters (OPA/Gatekeeper, OTel Collector)
  eks/               # EKS-only workloads (ARC runner controller, Karpenter NodePools, example ALB Ingress)
  vm-tier/           # VM-cluster-only manifests
policy/              # Gatekeeper constraint templates and constraints
.github/workflows/   # CI/CD: Terraform plan/apply, reusable workflow components
docs/                # Architecture, decision stack, pitfalls, runbooks, interview talking points, executive summary
```

## Build Roadmap

This is being built in phases, each independently demonstrable:

- [x] **Phase 0 — Repo scaffolding & Terraform foundation.** Directory structure, remote state backend (S3 + DynamoDB), shared VPC module, Terragrunt root config, CI skeleton.
- [x] **Phase 1 — Cloud-native tier.** EKS cluster + core system node group + IRSA (generic module), Karpenter controller (IAM, Spot-interruption SQS/EventBridge, Helm release) and its default NodePool/EC2NodeClass.
- [x] **Phase 2 — Self-hosted CI.** GitHub Actions Runner Controller (ARC) on EKS, GitHub App credentials in Secrets Manager, optional runner-pod IRSA, ephemeral autoscaled runner pods on a Spot-first CI-only Karpenter NodePool. Fully proven end to end against a real GitHub App and a real repo — see [Live Environment Status](#live-environment-status) below.
- [x] **Phase 3 — VM tier.** "On-prem" VPC, persistent EC2 ASGs (control-plane + worker node groups), SSM-only IAM (no SSH), kubeadm bootstrap + Calico CNI via Ansible over the SSM connection plugin.
- [x] **Phase 4 — Hybrid networking.** Real Site-to-Site VPN (VGW + self-managed strongSwan customer gateway, configured via Ansible over SSM) linking the cloud and on-prem VPCs, a Route 53 private hosted zone associated with both, and the AWS Load Balancer Controller for ALB Ingress on EKS.
- [x] **Phase 5 — Shared module registry discipline.** All 13 modules git-tagged `modules/<name>/v1.0.0`; every live stack (both tiers) consumes its module through that tag, not a local path — `cloud-vpc` and `onprem-vpc` both pull the identical `modules/vpc/v1.0.0`. The five EKS-controller stacks' duplicated `helm` provider boilerplate now lives once, in a Terragrunt `_envcommon` include.
- [x] **Phase 6 — Nexus Sonatype.** Dedicated EC2 instance (not containerized), standalone EBS data volume that outlives instance replacement, S3 lifecycle-managed daily backups, and a full [restore runbook](docs/runbooks/nexus-backup-restore.md).
- [x] **Phase 7 — Policy parity.** OPA/Gatekeeper controller on both clusters (Terraform+Helm on EKS, Ansible+Helm on the VM tier — same chart version/config, different invocation), with the same `ConstraintTemplate`/`Constraint` YAML `kubectl`-applied identically to both.
- [x] **Phase 8 — Federated observability.** Amazon Managed Prometheus (+ its managed Alertmanager) and Amazon Managed Grafana, an OpenTelemetry Collector on both tiers sharing one literal pipeline-config file, and CloudWatch alarms (EC2 status checks, VPN tunnel state) routed to PagerDuty/OpsGenie via SNS in parallel to Prometheus-evaluated alerts.
- [x] **Phase 9 — Runbooks & on-call discipline.** [`docs/runbooks/on-call-triage.md`](docs/runbooks/on-call-triage.md), a first-response guide keyed off the exact alarm names/thresholds in `terraform/modules/observability`. Cost allocation tags per team as two mechanisms: `terraform/modules/cost-allocation-tags` activates `Project`/`Environment`/`Tier`/`CostCenter` for AWS resources (now `Active` in Cost Explorer — see below), and the pre-existing `require-team-label.yaml` Gatekeeper constraint bridges into Cost Explorer via AWS's Split Cost Allocation Data for EKS once tenant workloads exist.

## Live Environment Status

Every phase above is code-complete, but code-complete isn't the same claim as "runs." As of **2026-09-20**, the full fleet described above has actually been applied to a real AWS account and verified against real infrastructure — not just `terraform validate`/`plan` or mocked outputs — with every bug that only a real apply could surface found and fixed in place (see each affected module's own README for the specifics: `eks-cluster`, `iam-irsa`, `karpenter`, `arc`, `observability`, `otel-collector`, `vm-k8s-asg`).

Every "Live" claim below has a concrete, reproducible artifact behind it — not just "it applied cleanly":

| Area | Status | Proof |
|---|---|---|
| Cloud tier (EKS, Karpenter, ALB Ingress, Gatekeeper) | Live | Karpenter scale-out verified end to end: a real oversized pod forced a Spot `r7a.medium` to launch, join, run the pod, and get consolidated away again afterward — `kubectl get nodeclaim -o jsonpath='{.status.conditions}'` showed `Launched=True`/`Registered=True`/`Initialized=True`/`Ready=True`. Gatekeeper confirmed live by a real admission-webhook rejection of a privileged, `:latest`-tagged, limit-less test pod. |
| VM tier (kubeadm, Calico, Gatekeeper, OTel Collector) | Live | All 3 nodes `Ready` per `kubectl get nodes`; the identical admission-webhook rejection above reproduced on this cluster too, confirming real policy parity, not just identical YAML. |
| Hybrid networking (VPN, DNS, Nexus) | Live | Both IPsec tunnels `ESTABLISHED` per `ipsec status` on the gateway instance (`10.1.0.0/16 === 10.0.0.0/16`); Nexus installed with its systemd backup timer enabled. |
| Observability — metrics pipeline (AMP, OTel, CloudWatch alarms) | Live | OTel Collector pods `1/1 Running` on both tiers, remote-writing to the same AMP workspace (confirmed via IMDS-authenticated `aps:RemoteWrite`, no static credentials). |
| Observability — Grafana data source | **Live** | Real root cause found first: `grafana_admin_sso_user_ids` had been left `[]` and the account's IAM Identity Center directory had zero users — nobody could ever sign in. Fixed by creating a real SSO user and granting it `ADMIN` via Terraform (verified with `aws grafana list-permissions`), then added the Prometheus data source by hand through the actual Grafana UI: SigV4 auth, `Workspace IAM Role` (no static credentials), pointed at `hybrid-fleet-amp`. Grafana's own "Save & test" reported `Successfully queried the Prometheus API`; independently re-confirmed via a second, now-deleted read-only service account token hitting `GET /api/datasources`, which returned the persisted data source with `sigV4Auth: true`, `sigV4AuthType: ec2_iam_role`. |
| Cost allocation tags (AWS resources + EKS Kubernetes labels) | **Active** | `aws ce list-cost-allocation-tags --status Active` returns all 10: `Project`/`Environment`/`Tier`/`CostCenter` (`Type: UserDefined`) plus all six `aws:eks:*` Split Cost Allocation Data tags (`Type: AWSGenerated`) — the latter was originally assumed to be a Billing-console-only toggle; checking a live account found it activates through the exact same `ce:UpdateCostAllocationTagsStatus` API, now Terraform-managed via `eks_split_cost_allocation_tag_keys` (see [`terraform/modules/cost-allocation-tags`](terraform/modules/cost-allocation-tags/)'s README for the full story). |
| ARC runner scale set | **Live** | Registered against a real GitHub App and a real repo, then proven with an actual job: [run 35542350874](https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform/actions/runs/35542350874) completed `success` in 40s on ephemeral pod `hybrid-fleet-runners-ptllt-runner-jm7l9`, which registered with GitHub, ran `actions/checkout@v4` against this repo's real `main` (`2b065481...`), and tore itself down immediately after — see [`.github/workflows/arc-smoke-test.yml`](.github/workflows/arc-smoke-test.yml), safe to re-run anytime as a regression check. |

## Getting Started

Prerequisites: an AWS account, Terraform >= 1.7, Terragrunt >= 0.58, `kubectl`, `helm`, `ansible`, an SSM-enabled AWS CLI profile.

```bash
# 1. Bootstrap remote state (one-time, per AWS account)
cd terraform/live/global/state-backend
terraform init && terraform apply

# 2. Both VPCs first — everything else in either tier needs one of these.
cd terraform/live/dev/cloud-vpc  && terragrunt init && terragrunt apply
cd ../onprem-vpc                 && terragrunt init && terragrunt apply

# 3. EKS, then its controllers (each needs ../eks's outputs; karpenter/arc/
#    alb-ingress-controller/opa-gatekeeper don't depend on each other, so
#    this sub-order doesn't matter beyond all needing eks first)
cd ../eks                        && terragrunt init && terragrunt apply
cd ../karpenter                  && terragrunt init && terragrunt apply
cd ../arc                        && terragrunt init && terragrunt apply
cd ../alb-ingress-controller     && terragrunt init && terragrunt apply
cd ../opa-gatekeeper              && terragrunt init && terragrunt apply

# 4. Apply the kubectl-managed cluster-native resources (Karpenter
#    NodePools/EC2NodeClass, the OPA/Gatekeeper policy content, and —
#    after registering runners, see terraform/modules/arc/README.md — the
#    ARC runner scale set)
aws eks update-kubeconfig --name hybrid-fleet-eks --region us-east-1
kubectl apply -f kubernetes/eks/karpenter/
kubectl apply -f kubernetes/base/opa-gatekeeper/ -f policy/gatekeeper-constraints/

# 5. Hybrid networking, in dependency order: DNS first (nexus's internal
#    record depends on it), then the Site-to-Site VPN (then configure
#    strongSwan — see ansible/README.md).
cd ../dns  && terragrunt init && terragrunt apply
cd ../vpn  && terragrunt init && terragrunt apply

# 6. Nexus — depends on ../dns (done above); install it once applied, see
#    ansible/README.md for the full Ansible wiring steps.
cd ../nexus && terragrunt init && terragrunt apply

# 7. Observability — depends on ../vpn and ../nexus (both just applied,
#    for the VPN-tunnel and Nexus-status-check CloudWatch alarms), then
#    otel-collector depends on ../observability for its AMP remote-write
#    grant. Getting this order wrong is exactly the mistake to avoid: both
#    dependencies are REAL (mock_outputs_allowed_terraform_commands
#    excludes "apply"), so applying observability any earlier just fails
#    outright rather than silently using placeholder ARNs.
cd ../observability   && terragrunt init && terragrunt apply
cd ../otel-collector  && terragrunt init && terragrunt apply

# 8. VM tier — vm-k8s also depends on ../observability (for its own AMP
#    remote-write IAM grant), so it comes after step 7, not interleaved
#    with onprem-vpc back in step 2. Then bootstrap kubeadm + Gatekeeper +
#    the OTel Collector on it over SSM (no SSH) — see ansible/README.md
#    for the full Ansible wiring steps.
cd ../vm-k8s && terragrunt init && terragrunt apply
# (ansible-playbook playbooks/bootstrap-k8s.yml && playbooks/configure-policy.yml
#  && playbooks/configure-observability.yml, then kubectl apply -f
#  kubernetes/base/opa-gatekeeper/ -f policy/gatekeeper-constraints/ against
#  the VM-tier kubeconfig too, to actually complete policy parity)

# 9. Activate cost allocation tags — apply this LAST, and not until the
#    above tags have existed on a resource for ~24h (AWS requirement, see
#    terraform/modules/cost-allocation-tags/README.md)
cd ../../global/cost-allocation-tags && terragrunt init && terragrunt apply
```

See [`docs/architecture.md`](docs/architecture.md) for the full system diagram and [`docs/runbooks/`](docs/runbooks/) for operational procedures.

## License

See [`LICENSE`](LICENSE).
