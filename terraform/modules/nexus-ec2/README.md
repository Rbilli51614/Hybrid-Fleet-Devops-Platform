# nexus-ec2

Nexus Sonatype OSS on a dedicated EC2 instance — deliberately **not** containerized on either K8s tier. Shared infra for both, reachable on port 8081 from whichever CIDRs you allow (typically both the cloud and on-prem VPC CIDRs, the latter reachable over the Phase 4 Site-to-Site VPN). SSM-only access, same as the rest of the VM tier — no SSH, no public IP.

Versioned via git tags (`modules/nexus-ec2/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

Terraform's job stops at "the box exists, the data volume is attached, and it's SSM-reachable" — Java/Nexus install, mounting the data volume, and the S3 backup cron are [`ansible/roles/nexus`](../../../ansible/roles/nexus/), same split as the rest of the repo. See [`docs/runbooks/nexus-backup-restore.md`](../../../docs/runbooks/nexus-backup-restore.md) for the operational procedure this all supports.

## Why the data volume is a standalone resource, not part of a launch template

Everything else in this repo's VM tier (`vm-k8s-asg`) treats instances as disposable — an ASG replaces a failed node and Ansible re-bootstraps it. Nexus is the opposite case on purpose: it's a single "pet," and its blob store (the actual artifacts) must survive an instance replacement, not be recreated with it. `aws_ebs_volume.nexus_data` is created and attached independently of the instance (`aws_volume_attachment`), with `lifecycle { prevent_destroy = true }` — if you ever need to actually tear this down, that block has to be removed deliberately first. That's the point: a real accidental `terraform destroy` shouldn't be able to take your artifact history with it.

## Example

```hcl
module "nexus" {
  source = "git::https://github.com/<org>/Hybrid-Fleet-Devops-Platform.git//terraform/modules/nexus-ec2?ref=modules/nexus-ec2/v1.0.0"

  name               = "hybrid-fleet"
  vpc_id             = module.onprem_vpc.vpc_id
  private_subnet_id  = module.onprem_vpc.private_subnet_ids[0]

  allowed_cidr_blocks = ["10.0.0.0/16", "10.1.0.0/16"] # cloud + on-prem VPC CIDRs

  route53_zone_id  = module.private_dns.zone_id
  dns_record_name  = "nexus.hybrid-fleet.internal"
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — |
| `vpc_id` / `private_subnet_id` | Where Nexus lives — the on-prem VPC, alongside the rest of the VM tier | `string` | — |
| `allowed_cidr_blocks` | CIDRs allowed to reach port 8081 | `list(string)` | — |
| `ami_ssm_parameter` | SSM path resolving to the instance's AMI | `string` | latest Ubuntu 22.04 LTS |
| `instance_type` | Instance size | `string` | `"t3.large"` |
| `root_volume_size_gb` | OS volume size (not the data volume) | `number` | `20` |
| `data_volume_size_gb` | Blob store volume size | `number` | `100` |
| `data_volume_device_name` | Device name the data volume attaches as | `string` | `"/dev/xvdf"` |
| `backup_transition_ia_days` / `backup_transition_glacier_days` / `backup_expiration_days` | S3 backup lifecycle timings | `number` | `30` / `90` / `365` |
| `route53_zone_id` / `dns_record_name` | Optional internal DNS record | `string` | `null` |
| `tags` | Extra tags applied to all resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `instance_id` | Target for SSM Session Manager access |
| `private_ip` / `dns_name` | How to reach Nexus |
| `backup_bucket_name` | S3 bucket the Ansible backup script uploads to |
| `data_volume_id` | The `prevent_destroy`-protected blob store volume |
