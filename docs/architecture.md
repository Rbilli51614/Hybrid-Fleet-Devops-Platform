# Architecture

## Problem

Organizations that grow through acquisition or long infrastructure lifecycles rarely run one clean, homogeneous stack. A common real-world shape: newer workloads run on managed Kubernetes (EKS) while legacy or data-center-bound workloads run on self-managed Kubernetes on VMs (e.g. Nutanix NKP, kubeadm, k3s). Left unmanaged, this produces:

- No consistent policy enforcement across the two K8s environments
- Duplicated (and drifting) Terraform modules and GitHub Actions workflows per team
- Self-hosted CI runners provisioned ad hoc, with inconsistent scaling and security posture
- No single observability plane across cloud-native and VM-based compute
- Artifact management (Nexus/Sonatype) running as an unmanaged pet on a VM with no backup discipline
- On-call engineers troubleshooting systems they didn't build, with no runbook discipline

## Solution

A **Hybrid Fleet DevOps Platform**: a single control plane that gives cloud-native (EKS) and self-managed VM-based Kubernetes clusters shared identity, shared CI/CD tooling, shared policy, and shared observability — without forcing the VM tier to become cloud-native.

Core components:

- **Two Kubernetes tiers**: EKS with Karpenter (cloud-native, autoscaled) + a self-managed kubeadm/k3s cluster on a persistent EC2 Auto Scaling Group (stands in for Nutanix NKP on VMs — same operational shape: you own the control plane, the CNI, the upgrades).
- **Self-hosted GitHub Actions Runner Controller (ARC)** running as ephemeral, autoscaled runner pods on EKS, registered against the org's GitHub App.
- **Shared Terraform module registry** (versioned, git-tag based) consumed by both clusters' IaC, enforced via Terragrunt.
- **Nexus Sonatype OSS** on a dedicated EC2 instance (deliberately *not* containerized-on-K8s) with EBS + S3-backed backup and restore runbook.
- **Federated observability**: Amazon Managed Prometheus + Grafana scraping both clusters (via remote-write from the VM tier over a private link), OpenTelemetry Collector as the vendor-neutral ingestion layer, CloudWatch for AWS-native resources.
- **Policy parity**: OPA/Gatekeeper deployed identically on both clusters so a workload is admitted (or rejected) under the same rules regardless of which tier it runs on.

## Diagram

```
                                   ┌─────────────────────────┐
                                   │        Route 53          │
                                   │   (internal DNS + ACM)   │
                                   └────────────┬─────────────┘
                                                │
                        ┌───────────────────────┼───────────────────────┐
                        │                        │                        │
                ┌───────▼────────┐      ┌────────▼─────────┐    ┌─────────▼─────────┐
                │   VPC: Cloud    │      │  Site-to-Site VPN │    │  VPC: "On-Prem"    │
                │   (EKS tier)    │◄────►│  (simulates DC    │◄──►│  Simulation Tier    │
                │                 │      │  interconnect)    │    │  (VM-based K8s)     │
                └───────┬─────────┘      └────────────────────┘    └─────────┬──────────┘
                        │                                                    │
        ┌───────────────┼───────────────┐                    ┌───────────────┼───────────────┐
        │               │               │                    │               │               │
┌───────▼──────┐ ┌──────▼───────┐ ┌─────▼──────┐    ┌─────────▼────────┐ ┌────▼─────┐ ┌───────▼──────┐
│  EKS Cluster │ │  ARC Runner  │ │ Karpenter  │    │ kubeadm/k3s on   │ │  Nexus   │ │  OTel Collector│
│  (app + CI)  │ │  Pods (ARC)  │ │ NodePools  │    │ EC2 ASG (persist)│ │ Sonatype │ │  (VM-side)    │
└───────┬──────┘ └──────┬───────┘ └────────────┘    └─────────┬────────┘ │ (EC2+EBS)│ └───────┬──────┘
        │               │                                     │          └────┬─────┘         │
        │        ┌──────▼───────┐                             │               │               │
        │        │ GitHub Actions│                             │        ┌──────▼──────┐        │
        │        │ (cloud, jobs  │                             │        │ S3 backup    │        │
        │        │ dispatched to │                             │        │ bucket       │        │
        │        │ ARC runners)  │                             │        └─────────────┘        │
        │        └───────────────┘                             │                                │
        │                                                       │                                │
        └───────────────────────┬───────────────────────────────┴────────────────────────────────┘
                                 │
                       ┌─────────▼──────────┐
                       │ Amazon Managed      │
                       │ Prometheus + Grafana│
                       │ (federated scrape/  │
                       │  remote-write)      │
                       └─────────┬──────────┘
                                 │
                       ┌─────────▼──────────┐
                       │ CloudWatch + Alarms │
                       │ → Alertmanager →    │
                       │   PagerDuty/OpsGenie│
                       └─────────────────────┘

Shared Terraform module registry (versioned via git tags) + Terragrunt
   → consumed by both the EKS-tier and VM-tier IaC stacks
OPA/Gatekeeper deployed identically on both K8s clusters
IAM: IRSA for EKS workloads; SSM-based (no SSH) role for VM tier
```

## Module registry convention

The brief calls for an S3-backed private module registry. This repo implements the same versioning discipline with a lower-overhead mechanism: modules under `terraform/modules/` are referenced from `terraform/live/**` via git source refs pinned to semantic-version tags, e.g.:

```hcl
source = "git::https://github.com/<org>/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vpc?ref=modules/vpc/v1.0.0"
```

Tags follow `modules/<module-name>/vX.Y.Z`. This gives every consumer (both K8s tiers' IaC) the same version-pinning and breaking-change discipline a hosted private registry would, without a paid dependency. See [`decision-stack.md`](decision-stack.md) for the tradeoff discussion.

## Why EKS and Karpenter are separate Terragrunt stacks

`terraform/live/dev/eks` and `terraform/live/dev/karpenter` are two Terragrunt units, not one, even though Karpenter only exists to serve the EKS cluster. Karpenter's Helm release needs a `helm` provider configured with that cluster's own endpoint/CA/auth token — and a provider block can't be configured from a resource created in the *same* `terraform apply` without the well-known "provider config depends on a resource" chicken-and-egg problem. Splitting them into two stacks, with `karpenter` reading `eks`'s outputs through a Terragrunt `dependency` block, avoids it entirely: `eks` applies and finishes, *then* `karpenter`'s generated `helm_provider.tf` points at a cluster that already exists.

The same reasoning is why the EKS cluster ships with a small on-demand **core system node group** (see the `eks-cluster` module): the Karpenter controller has to run somewhere before it can provision any capacity of its own, so it's pinned there via `nodeSelector` rather than depending on Karpenter to bootstrap itself.
