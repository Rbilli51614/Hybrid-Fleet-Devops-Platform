# ansible

Config management for the VM tier, the on-prem VPN gateway, and Nexus. Wires into `docs/jd-mapping.md`'s "IaC + config management (Terraform, Ansible/Chef/Puppet)" row. The VM-tier half bootstraps the self-managed kubeadm cluster that `terraform/live/dev/vm-k8s` provisions — the "you own the upgrades, the CNI, the control plane" half of the hybrid fleet — see [`docs/architecture.md`](../docs/architecture.md).

Terraform's job stops at "the box exists, is reachable via SSM, and has an IAM role"; everything past that (containerd, kubeadm, kubelet, cluster init/join, CNI; strongSwan tunnel config) is Ansible's, run entirely over AWS Systems Manager Session Manager — **no SSH key pair, no open port 22, no bastion** anywhere in either tier. See [`docs/decision-stack.md`](../docs/decision-stack.md) for why.

## Layout

```
ansible.cfg                    # points at inventories/dev by default, enables the aws_ec2 inventory plugin
requirements.yml                # collections: amazon.aws, community.aws, ansible.posix, kubernetes.core
inventories/dev/
  aws_ec2.yml                   # dynamic inventory — discovers nodes by tag, groups by Role, connects via SSM
  group_vars/all.yml            # wires Terraform outputs (join_token_ssm_path, etc.) into the playbook
playbooks/
  bootstrap-k8s.yml             # site playbook: common prereqs -> control-plane init -> worker join
  configure-vpn-gateway.yml     # configures strongSwan on the on-prem VPN gateway instance
  configure-nexus.yml           # installs Nexus, mounts its data volume, sets up the S3 backup timer
  configure-policy.yml          # installs the Gatekeeper controller on the VM-tier cluster
  configure-observability.yml   # installs the OpenTelemetry Collector on the VM-tier cluster
roles/
  k8s-common/                   # swap off, kernel modules/sysctl, containerd, pinned kubeadm/kubelet/kubectl
  k8s-control-plane/            # kubeadm init, Calico CNI, publishes the join command to SSM Parameter Store
  k8s-worker/                   # waits for and consumes that join command, kubeadm join
  vpn-gateway/                  # reads the negotiated tunnel config from SSM, renders + brings up strongSwan
  nexus/                        # Java + Nexus install, data-volume mount, systemd unit, daily S3 backup timer
  opa-gatekeeper/               # installs Helm (if missing) + the Gatekeeper chart, same version as the EKS side
  otel-collector/               # installs the same OTel Collector chart/pipeline as the EKS side, auth via IMDS
```

## Run

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml

# Wire in this environment's Terraform outputs (join_token_ssm_path etc.)
cd ../terraform/live/dev/vm-k8s
echo "join_token_ssm_path: \"$(terragrunt output -raw join_token_ssm_path)\"" \
  > ../../../../ansible/inventories/dev/group_vars/vm_k8s_outputs.yml

# terraform/modules/vm-k8s-asg provisions the S3 bucket the aws_ssm
# connection plugin needs for file-transfer staging — just export it:
export ANSIBLE_SSM_BUCKET="$(terragrunt output -raw ssm_transfer_bucket_name)"
cd ../../../../ansible

ansible-playbook playbooks/bootstrap-k8s.yml
```

Idempotent: safe to re-run after Terraform replaces an unhealthy instance — each role checks whether its node has already initialized/joined before doing anything (see [`terraform/modules/vm-k8s-asg/README.md`](../terraform/modules/vm-k8s-asg/README.md) for the kubeadm-token-vs-ASG-replacement tradeoff this depends on).

### VPN gateway

After `terraform/live/dev/vpn` has applied:

```bash
ansible-playbook playbooks/configure-vpn-gateway.yml
```

No extra Terraform-output wiring needed — `terraform/modules/vpn`'s `tunnel_parameter_path` default (`/hybrid-fleet/vpn`) already matches `ansible/roles/vpn-gateway/defaults/main.yml`; override `-e tunnel_parameter_path=...` if you changed it in the live stack. If a tunnel won't come up, cross-check `ansible/roles/vpn-gateway/defaults/main.yml`'s IKE/ESP parameters against the real, connection-specific config: `terragrunt output -raw customer_gateway_configuration` from `terraform/live/dev/vpn`.

### Nexus

After `terraform/live/dev/nexus` has applied:

```bash
cd terraform/live/dev/nexus
ansible-playbook ../../../../ansible/playbooks/configure-nexus.yml \
  -e "nexus_backup_s3_bucket=$(terragrunt output -raw backup_bucket_name)"
```

Full operational procedure — how the backup timer works, and how to restore — in [`docs/runbooks/nexus-backup-restore.md`](../docs/runbooks/nexus-backup-restore.md).

### Policy parity (Gatekeeper)

After `playbooks/bootstrap-k8s.yml` has run (needs the control-plane's kubeconfig):

```bash
ansible-playbook playbooks/configure-policy.yml
```

Installs only the Gatekeeper controller, at the same chart version/config as [`terraform/modules/opa-gatekeeper`](../terraform/modules/opa-gatekeeper/) installs on EKS. The actual policy content is applied separately, identically to both clusters — see [`kubernetes/base/opa-gatekeeper/README.md`](../kubernetes/base/opa-gatekeeper/README.md).

### Federated observability (OpenTelemetry Collector)

After `terraform/live/dev/observability` has applied and `playbooks/bootstrap-k8s.yml` has run:

```bash
cd terraform/live/dev/observability
ansible-playbook ../../../../ansible/playbooks/configure-observability.yml \
  -e "amp_remote_write_url=$(terragrunt output -raw amp_remote_write_url)"
```

Renders the exact same pipeline config as [`terraform/modules/otel-collector`](../terraform/modules/otel-collector/) installs on EKS — see [`kubernetes/base/otel-collector/README.md`](../kubernetes/base/otel-collector/README.md) for how "the same file, two render mechanisms" actually holds. Authenticates to Amazon Managed Prometheus as this instance's own IAM role via IMDS — requires `terraform/live/dev/vm-k8s` to have been re-applied after `../observability` exists, so its `amp_workspace_arn` grant is in place (see `terraform/modules/vm-k8s-asg/README.md`).

Validated in this repo with `ansible-playbook --syntax-check`, and every role's Jinja templates test-rendered offline with representative variables (no live AWS connectivity needed for either) — real execution needs the relevant Terraform stack actually provisioned and, for the VM tier, an `ANSIBLE_SSM_BUCKET`.
