# vm-k8s-asg

Persistent EC2 Auto Scaling Groups standing in for on-prem VM-based Kubernetes (e.g. Nutanix NKP) — one group per node role (`control-plane`, `worker`), each self-healing via the ASG rather than elastically scaled. IAM is SSM Session Manager only: no SSH key pair, no open port 22, no bastion. This module provisions the boxes; Ansible ([`ansible/playbooks/bootstrap-k8s.yml`](../../../ansible/playbooks/bootstrap-k8s.yml)) installs and bootstraps kubeadm on them afterward, over the SSM connection plugin — see [`docs/decision-stack.md`](../../../docs/decision-stack.md) for why the split.

Versioned via git tags (`modules/vm-k8s-asg/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## AWS security group descriptions reject characters this repo's prose uses constantly

A real apply failed outright — `InvalidParameterValue: Invalid security group description` — on a description reading "...control plane <-> workers..."; a second one, on the very next resource, for an apostrophe in "...VPC's NAT gateway...". AWS security group (and security group rule) descriptions only accept `a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*` — no `<`, `>`, or `'`, among others. This is an AWS-side charset restriction, not an HCL type constraint, so `terraform validate` never flags it; only a real `CreateSecurityGroup`/`AuthorizeSecurityGroupIngress` call does. Worth a second look at any resource description written in this repo's usual prose style before assuming it'll apply cleanly.

## `community.aws.ssm_parameter` needs more than `PutParameter`/`GetParameter`, discovered one `AccessDeniedException` at a time

`ansible/roles/k8s-control-plane`'s `community.aws.ssm_parameter` task (publishing the kubeadm join command) does its own idempotency checking before writing, and that costs more IAM actions than the actual write does — two more were missing, each only surfacing once a real run got far enough to reach it:

- **`ssm:DescribeParameters`** — called first, to check whether the parameter already exists. Confirmed against AWS's own IAM action reference: this action has *no* resource-level permission support whatsoever, so it can only ever be granted with `Resource: "*"` — a statement scoped to the specific parameter ARN could never satisfy it, no matter what's listed in `actions`. `aws_iam_policy_document.join_token_parameter` grants it via a separate `dynamic "statement"`, `control-plane`-only, rather than trying to fold it into the ARN-scoped one.
- **`ssm:ListTagsForResource`** — called next, to compare the parameter's current tags. Unlike `DescribeParameters`, this one *does* support resource-level scoping (AWS's error named the specific parameter ARN, not `*`), so it's just added to the same ARN-scoped statement as `PutParameter`/`GetParameter`.

## Example

```hcl
module "vm_k8s" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vm-k8s-asg?ref=modules/vm-k8s-asg/v1.0.3"

  name         = "hybrid-fleet-vm-k8s"
  cluster_name = "hybrid-fleet-vm-k8s"
  vpc_id       = module.onprem_vpc.vpc_id
  subnet_ids   = module.onprem_vpc.private_subnet_ids

  node_groups = {
    control-plane = {
      role          = "control-plane"
      instance_type = "t3.medium"
      desired_size  = 1
      min_size      = 1
      max_size      = 1
    }
    worker = {
      role          = "worker"
      instance_type = "t3.medium"
      desired_size  = 2
      min_size      = 2
      max_size      = 2
    }
  }
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — |
| `cluster_name` | Logical cluster name; tags instances and scopes the join-token SSM path | `string` | — |
| `vpc_id` | VPC (the "on-prem" one, not cloud/EKS) | `string` | — |
| `subnet_ids` | Private subnets, no public IPs | `list(string)` | — |
| `ami_ssm_parameter` | SSM path resolving to the AMI to launch | `string` | latest Ubuntu 22.04 LTS |
| `node_groups` | Map of node group name → `{role, instance_type, desired_size, min_size, max_size, root_volume_size_gb?}` | `map(object(...))` | — |
| `join_token_ssm_path` | SSM Parameter Store path for the kubeadm join command exchange | `string` | `"/<cluster_name>/join-command"` |
| `amp_workspace_arn` | If set, grants every node `aps:RemoteWrite` on this Amazon Managed Prometheus workspace — see [`ansible/roles/otel-collector`](../../../ansible/roles/otel-collector/) | `string` | `null` |
| `tags` | Extra tags applied to all resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `security_group_id` | Shared SG attached to every node (self-referencing, no external ingress) |
| `node_role_arns` | Map of node group key → IAM role ARN |
| `autoscaling_group_names` | Map of node group key → ASG name |
| `join_token_ssm_path` | For wiring into the Ansible playbook's SSM parameter lookups |
| `ssm_transfer_bucket_name` | S3 bucket for the Ansible `aws_ssm` connection plugin's file-transfer staging — export as `ANSIBLE_SSM_BUCKET` (see [`ansible/README.md`](../../../ansible/README.md)) |

## A pitfall this doesn't solve

kubeadm bootstrap tokens expire after 24h by default; an ASG can replace an unhealthy worker node at any time, including well past that window. The Ansible worker role generates the join command with `--ttl 0` (non-expiring) as a pragmatic tradeoff for a self-healing group — the real fix at scale is a small token-rotation job (cron/Lambda) refreshing a short-lived token instead of one static non-expiring one. Worth doing before this pattern goes anywhere near production; out of scope for a portfolio cluster of this size.
