# eks-cluster

EKS control plane, IAM OIDC provider (for IRSA), a small on-demand core system node group that hosts kube-system components — including the Karpenter controller itself, which must run somewhere before it can provision any further capacity — and the four EKS-managed addons that keep that node group usable (`vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`).

Versioned via git tags (`modules/eks-cluster/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Why `aws-ebs-csi-driver` gets its own IRSA role and the other three addons don't

`vpc-cni`, `coredns`, and `kube-proxy` don't call AWS APIs on their own behalf — they only need what the node's own networking/DNS already provides. `aws-ebs-csi-driver` does (EC2 `DescribeVolumes`, `CreateVolume`, `AttachVolume`, etc.), so it needs real IAM permissions the same way every other AWS-calling controller in this repo gets them: IRSA, via this module's own `../iam-irsa` module, scoped to the addon's well-known service account (`kube-system:ebs-csi-controller-sa`) with the `AmazonEBSCSIDriverPolicy` managed policy attached. This was caught on a real apply, not by `terraform validate` or a mocked plan: without it, the addon's controller pods sit in `CrashLoopBackOff` with `"no EC2 IMDS role found"` — there's no fallback credential path once a pod is on the network, not even to the node's own instance role.

## Default bumped from 1.31 to 1.36

The prior default (1.31) had already aged out of standard support by the time this was revisited — confirmed via `aws eks describe-cluster-versions`, which showed 1.31 sitting in `EXTENDED_SUPPORT` (its standard support ended 2025-11-25, meaning AWS bills extra per cluster-hour for it) while 1.36 was the newest version still in `STANDARD_SUPPORT`. Nothing else in this module needed to change to support the jump: `cluster_addons`' `version` already defaults to `null` per addon, so AWS resolves the compatible addon version for whatever `kubernetes_version` is set rather than this module pinning one, and `core_node_ami_type` selects an AMI type rather than a specific AMI ID, so it resolves the right AL2023 AMI for the target version automatically too. `ansible/roles/k8s-common/defaults/main.yml`'s `kubernetes_apt_series`/`kubernetes_package_version` were bumped alongside this to keep the VM tier on a comparable version, per that file's own comment.

Note this only affects a *fresh* cluster creation. An already-running cluster can't jump straight from 1.31 to 1.36 — AWS requires sequential one-minor-version-at-a-time upgrades, so an existing cluster needs five separate `kubernetes_version` bumps and applies (1.31→1.32→...→1.36), not one.

## Example

```hcl
module "eks" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/eks-cluster?ref=modules/eks-cluster/v1.0.3"

  cluster_name       = "hybrid-fleet-eks"
  kubernetes_version = "1.36"
  vpc_id             = module.cloud_vpc.vpc_id
  subnet_ids         = module.cloud_vpc.private_subnet_ids

  admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admins"]
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | Name of the EKS cluster | `string` | — |
| `kubernetes_version` | Control plane Kubernetes minor version. AWS only keeps a rolling ~6-version window creatable/upgradable via the API — a pinned version eventually ages out (`CreateNodegroup` starts rejecting it outright), independent of this module; revisit periodically | `string` | `"1.36"` |
| `vpc_id` | VPC for the cluster and core node group | `string` | — |
| `subnet_ids` | Subnets for control plane ENIs | `list(string)` | — |
| `core_node_subnet_ids` | Subnets for the core node group (defaults to `subnet_ids`) | `list(string)` | `[]` |
| `endpoint_public_access` | Expose the API server publicly | `bool` | `true` |
| `endpoint_public_access_cidrs` | CIDRs allowed at the public endpoint | `list(string)` | `["0.0.0.0/0"]` |
| `admin_principal_arns` | IAM principals granted cluster-admin via access entries | `list(string)` | `[]` |
| `core_node_instance_types` | Instance types for the core node group | `list(string)` | `["t3.medium"]` |
| `core_node_ami_type` | EKS-optimized AMI family for the core node group | `string` | `"AL2023_x86_64_STANDARD"` |
| `core_node_desired_size` / `min_size` / `max_size` | Core node group sizing | `number` | `2` / `2` / `3` |
| `cluster_addons` | EKS-managed addons to install | `map(object({version=optional(string)}))` | vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver |
| `tags` | Extra tags applied to all resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `cluster_name`, `cluster_arn`, `cluster_endpoint`, `cluster_certificate_authority_data` | Cluster identity/connection details |
| `cluster_security_group_id` | EKS-managed cluster security group |
| `oidc_provider_arn`, `oidc_provider_url` | Used to build IRSA trust policies (see [`iam-irsa`](../iam-irsa/)) |
| `core_node_role_arn`, `core_node_role_name` | IAM role backing the core node group |

**Note:** `endpoint_public_access` defaults to `true` so `kubectl`/CI can reach the cluster without a bastion or the VPN link from Phase 4. Tighten this to `false` once the Site-to-Site VPN is in place, per [`docs/pitfalls.md`](../../../docs/pitfalls.md).
