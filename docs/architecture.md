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

`terraform/live/dev/arc` follows the same split for the same reason — its Helm-installed controller also needs a `helm` provider pointed at the already-existing EKS cluster.

## The Terraform/kubectl boundary for cluster-native resources

Both `karpenter` and `arc` follow the same pattern: Terraform owns the controller install and its cloud-side plumbing (IAM, SQS/EventBridge for Karpenter; Secrets Manager for ARC's GitHub App credentials), while the resources that describe *what the controller should actually do* — Karpenter's `NodePool`/`EC2NodeClass`, ARC's per-repo `gha-runner-scale-set` — are plain `kubectl`/`helm`-applied manifests under `kubernetes/eks/`, not Terraform-managed. Two reasons: those resources change per-team/per-repo far more often than cloud infra does, and it's the natural boundary for a GitOps tool (ArgoCD/Flux) to take over later without ever touching Terraform state.

## The VM tier: same IaC/config-mgmt split, a different mechanism

`terraform/modules/vm-k8s-asg` follows the same "Terraform provisions, something else configures" boundary as the EKS-tier modules, just with Ansible instead of Helm/kubectl on the other side of it. Terraform's job stops once the box exists: a launch template + Auto Scaling Group per node role (`control-plane`, `worker`), an IAM instance profile with `AmazonSSMManagedInstanceCore` and nothing else (no SSH key pair is ever created), and a security group with zero inbound rules from outside the group. Everything from containerd onward — kubeadm install, `kubeadm init`/`join`, the Calico CNI — is [`ansible/playbooks/bootstrap-k8s.yml`](../ansible/README.md), run entirely over Ansible's `aws_ssm` connection plugin (Session Manager, not SSH).

The one genuinely fiddly part: a control-plane and worker node need to exchange a `kubeadm join` command, but there's no SSH between them to do it directly, and the ASG can replace a worker at any time — long after a default 24h bootstrap token would have expired. The `k8s-control-plane` Ansible role publishes a **non-expiring** (`--ttl 0`) join command to an SSM Parameter Store path that only that specific cluster's node IAM roles can read/write (scoped per role by `vm-k8s-asg`'s IAM policies); the `k8s-worker` role polls that same path with a retry loop until it appears. It's a deliberate tradeoff, not an oversight — see [`terraform/modules/vm-k8s-asg/README.md`](../terraform/modules/vm-k8s-asg/README.md) for what the real fix looks like at scale.

This VM tier lives in its own "on-prem simulation" VPC (`terraform/live/dev/onprem-vpc`, CIDR `10.1.0.0/16`, non-overlapping with the cloud VPC's `10.0.0.0/16` on purpose — see below), reusing the same `vpc` module as the cloud tier with no EKS-specific tags applied.

## The Site-to-Site VPN: a real tunnel, not a diagram placeholder

Both VPCs in this repo are AWS VPCs in the same account — nothing about that forces the link between them to be fake. `terraform/modules/vpn` provisions a genuine AWS Site-to-Site VPN: a Virtual Private Gateway attached to the cloud VPC (the managed, "AWS" side — no different from what a real customer deploys), and a self-managed strongSwan instance in the on-prem VPC's public subnet standing in for the physical router a real DC interconnect would terminate at. The Elastic IP that instance needs is the *only* deliberate exception to "no public IPs in the on-prem VPC" from the VM tier — because it's playing the role of the on-prem network's own edge, which legitimately has a public-facing interface in the real world this setup simulates.

The same "Terraform provisions, Ansible configures" split shows up here too, but with a twist versus the kubeadm join command: there's no chicken-and-egg problem, because Terraform already knows the negotiated tunnel details (PSKs, endpoint addresses, inside `/30`s) the moment `aws_vpn_connection` is created — it writes them straight to SSM Parameter Store, and [`ansible/roles/vpn-gateway`](../ansible/README.md) reads them back to render strongSwan's config and bring the tunnels up. One real Terraform constraint worth knowing surfaced while building this: security-group rules that scope inbound IKE/NAT-T to AWS's own tunnel endpoint IPs can't use `for_each` over those addresses, because `for_each`'s key set has to be known at plan time and those IPs aren't known until the VPN connection exists — see `terraform/modules/vpn/README.md` for the fix (four singleton resources instead of one `for_each`).

## Nexus: a pet, not livestock, and that's deliberate

Everything else this repo builds treats compute as disposable — an ASG replaces a bad node, Ansible re-bootstraps it, nothing is lost because nothing stateful lived on the instance itself. `terraform/modules/nexus-ec2` is the one deliberate exception: Nexus is a single instance, and its blob store has to survive that instance being replaced, not be recreated along with it. The fix is structural, not a backup-and-hope-for-the-best: the EBS data volume is a standalone resource (`aws_ebs_volume` + `aws_volume_attachment`, not a launch-template-managed volume tied to instance lifecycle) with `lifecycle { prevent_destroy = true }`, so it reattaches to whatever instance exists rather than being torn down with the old one.

Nexus also sits at the point where the two K8s tiers' shared-infra story becomes concrete rather than aspirational: its security group allows port 8081 from *both* VPC CIDRs — the on-prem one directly, the cloud one only reachable because Phase 4's Site-to-Site VPN tunnel exists. Sequencing that dependency correctly (`terraform/live/dev/nexus` depends on `../cloud-vpc`, `../onprem-vpc`, and `../dns` for its internal Route 53 record) is Terragrunt doing exactly what it's for.

Backup discipline is a full runbook, not a TODO comment — see [`docs/runbooks/nexus-backup-restore.md`](../docs/runbooks/nexus-backup-restore.md) for what the daily systemd-timer-driven backup actually does and the step-by-step restore procedure, including the documented tradeoff (stop/tar/restart for consistency, at the cost of a brief window) and what the real fix looks like once that window is actually a problem.

On top of the tunnel: a Route 53 private hosted zone (`terraform/modules/private-dns`) associated with both VPCs, so either tier resolves the same internal names; and the AWS Load Balancer Controller (`terraform/modules/alb-ingress-controller`) on the EKS side, turning `Ingress` resources into real ALBs — its IAM policy is fetched from the controller's own GitHub release at apply time rather than hand-copied, for the same "don't transcribe something you can source authoritatively" reasoning as the tunnel's IKE/ESP parameters (see that module's README).
