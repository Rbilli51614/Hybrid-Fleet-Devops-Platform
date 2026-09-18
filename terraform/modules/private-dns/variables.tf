variable "zone_name" {
  description = "Private hosted zone name (e.g. \"hybrid-fleet.internal\"). Not a real public TLD — this zone is never delegated publicly, only resolved inside the associated VPCs."
  type        = string
}

variable "primary_vpc_id" {
  description = "VPC the zone is created against. Additional VPCs (var.additional_vpc_ids) are associated afterward — the AWS provider only lets a zone be created with one initial VPC association."
  type        = string
}

variable "additional_vpc_ids" {
  description = "Further VPC IDs to associate with the zone (same account/region) — e.g. both the cloud and on-prem VPCs, so either tier can resolve records in this zone."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to the hosted zone."
  type        = map(string)
  default     = {}
}
