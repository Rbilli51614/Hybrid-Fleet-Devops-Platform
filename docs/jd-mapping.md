# JD Requirement Mapping

Reference role: DevOps Engineer II / Platform Engineer (embedded model, hybrid cloud + on-prem). Reference JD: Fabletics — DevOps Engineer II.

| JD Requirement | Project Component |
|---|---|
| CI/CD on Jenkins + GitHub Actions, self-hosted runners | ARC-managed, autoscaled GitHub Actions runners on EKS |
| Kubernetes across EKS and NKP (VM environments) | EKS (Karpenter) + kubeadm/k3s on persistent EC2 ASG |
| Shared Terraform modules / reusable GitHub Actions components | Versioned module registry (git-tag pinned) + Terragrunt |
| Nexus Sonatype artifact repo on VMs | Nexus OSS on EC2 + EBS, S3-backed backup/restore runbook |
| AWS networking, IAM, storage, compute | VPC/VPN design, IRSA + SSM-based IAM, S3, EC2, EKS |
| Observability: logging, metrics, tracing | Amazon Managed Prometheus/Grafana + OpenTelemetry Collector + CloudWatch |
| On-call, incident triage across distributed systems | Alertmanager → PagerDuty/OpsGenie routing, versioned runbooks in-repo |
| IaC + config management (Terraform, Ansible/Chef/Puppet) | Terraform/Terragrunt for provisioning; Ansible for VM-tier k8s bootstrap and Nexus config |
| Comfort in Linux/VM-based environments | Nexus and the VM-tier Kubernetes cluster are both unmanaged, self-administered Linux hosts |
