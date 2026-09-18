variable "name" {
  description = "Name prefix for all resources created by this module."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ (same order as var.azs)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ (same order as var.azs)."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "If true, route all private subnets through one shared NAT Gateway instead of one per AZ. Cheaper, less resilient — fine for dev/portfolio use."
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "If set, tags subnets for EKS/Karpenter/ALB-ingress auto-discovery (kubernetes.io/cluster/<name>, kubernetes.io/role/elb, karpenter.sh/discovery)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
