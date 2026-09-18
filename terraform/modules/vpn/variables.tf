variable "name" {
  description = "Name prefix for all resources created by this module."
  type        = string
}

variable "cloud_vpc_id" {
  description = "The AWS-managed side of the tunnel: the cloud/EKS VPC. A real AWS Site-to-Site VPN's Virtual Private Gateway attaches here."
  type        = string
}

variable "cloud_vpc_cidr" {
  description = "CIDR of the cloud VPC — routed to from the on-prem side via the tunnel."
  type        = string
}

variable "cloud_private_route_table_ids" {
  description = "Private route table IDs in the cloud VPC to propagate the on-prem CIDR into (via VPN Gateway route propagation)."
  type        = list(string)
}

variable "onprem_vpc_id" {
  description = "The simulated \"customer\" side of the tunnel: the on-prem VPC."
  type        = string
}

variable "onprem_vpc_cidr" {
  description = "CIDR of the on-prem VPC — routed to from the cloud side via the tunnel, and the static route registered on the AWS VPN connection."
  type        = string
}

variable "onprem_public_subnet_id" {
  description = "Public subnet in the on-prem VPC to launch the self-managed VPN gateway (strongSwan) instance into. Must be public: this is the one box in the on-prem VPC that legitimately needs a routable IP, since it's standing in for a physical on-prem router/firewall terminating a real DC interconnect."
  type        = string
}

variable "onprem_private_route_table_ids" {
  description = "Private route table IDs in the on-prem VPC to add a route for the cloud CIDR into, via the VPN gateway instance's network interface (source/dest check disabled, acting as a router)."
  type        = list(string)
}

variable "ami_ssm_parameter" {
  description = "SSM Parameter Store path resolving to the AMI ID for the VPN gateway instance. Defaults to the latest published Ubuntu 22.04 LTS AMI."
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

variable "instance_type" {
  description = "Instance type for the VPN gateway. It only routes/encrypts traffic — a small instance is plenty."
  type        = string
  default     = "t3.micro"
}

variable "amazon_side_asn" {
  description = "BGP ASN for the AWS side of the tunnel (the Virtual Private Gateway). Unused for routing (this module uses static routes, not BGP) but required by the VGW resource."
  type        = number
  default     = 64512
}

variable "customer_side_asn" {
  description = "BGP ASN presented by the simulated customer gateway. Arbitrary/unused for the same reason as amazon_side_asn — 65000 is the conventional placeholder private ASN for exactly this case."
  type        = number
  default     = 65000
}

variable "tunnel_parameter_path" {
  description = "SSM Parameter Store path prefix Terraform writes the negotiated tunnel details (PSKs, endpoint/inside addresses) to, for the Ansible vpn-gateway role to read and render into a strongSwan config. No default: deliberately forces an explicit, cluster-specific path rather than a value that could collide across environments."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
