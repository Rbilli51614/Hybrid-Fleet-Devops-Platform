output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the created VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateway(s)."
  value       = aws_nat_gateway.this[*].id
}

output "private_route_table_ids" {
  description = "IDs of the private route table(s) — one if single_nat_gateway, one per AZ otherwise. Used by the vpn module for route propagation."
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "ID of the (single, shared) public route table."
  value       = aws_route_table.public.id
}
