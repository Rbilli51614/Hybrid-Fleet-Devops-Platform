variable "name" {
  description = "Name prefix for all resources created by this module."
  type        = string
}

variable "vpc_id" {
  description = "VPC Nexus is deployed into — the on-prem VPC, alongside the rest of the VM tier (see docs/architecture.md's diagram)."
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet for the Nexus instance. No public IP: reachable only from allowed_cidr_blocks and over SSM, same access model as the rest of the VM tier."
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Nexus on port 8081. Nexus is shared infra for both K8s tiers (see docs/decision-stack.md), so this should include both the on-prem VPC CIDR and — reachable over the Phase 4 Site-to-Site VPN — the cloud VPC CIDR."
  type        = list(string)
}

variable "ami_ssm_parameter" {
  description = "SSM Parameter Store path resolving to the AMI ID. Defaults to the latest published Ubuntu 22.04 LTS AMI."
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

variable "instance_type" {
  description = "Instance type. Nexus wants real memory (4GB+); t3.large gives it headroom without over-provisioning for a portfolio-scale repo."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Root (OS) volume size. Nexus's actual data lives on the separate data volume below, not here."
  type        = number
  default     = 20
}

variable "data_volume_size_gb" {
  description = "Size of the separate EBS volume holding Nexus's blob store (/nexus-data). Deliberately not part of the instance's root volume or a launch-template-managed volume: it must outlive any single instance replacement — see this module's README."
  type        = number
  default     = 100
}

variable "data_volume_device_name" {
  description = "Device name the data volume attaches as. Must match ansible/roles/nexus's expectation."
  type        = string
  default     = "/dev/xvdf"
}

variable "backup_transition_ia_days" {
  description = "Days after which S3 backup objects move Standard -> Standard-IA."
  type        = number
  default     = 30
}

variable "backup_transition_glacier_days" {
  description = "Days after which S3 backup objects move Standard-IA -> Glacier."
  type        = number
  default     = 90
}

variable "backup_expiration_days" {
  description = "Days after which S3 backup objects are deleted entirely."
  type        = number
  default     = 365
}

variable "route53_zone_id" {
  description = "Private hosted zone ID to create a DNS record in (see terraform/modules/private-dns). Null skips DNS entirely."
  type        = string
  default     = null
}

variable "dns_record_name" {
  description = "Fully-qualified DNS name to create (e.g. \"nexus.hybrid-fleet.internal\"), pointing at the instance's private IP. Ignored if route53_zone_id is null."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
