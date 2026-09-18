output "vpn_gateway_id" {
  description = "ID of the Virtual Private Gateway attached to the cloud VPC."
  value       = aws_vpn_gateway.cloud.id
}

output "vpn_connection_id" {
  description = "ID of the AWS Site-to-Site VPN connection."
  value       = aws_vpn_connection.this.id
}

output "onprem_gateway_instance_id" {
  description = "Instance ID of the self-managed strongSwan VPN gateway — target this for SSM Session Manager access."
  value       = aws_instance.onprem_gateway.id
}

output "onprem_gateway_public_ip" {
  description = "Elastic IP of the on-prem gateway instance (the AWS Customer Gateway's ip_address)."
  value       = aws_eip.onprem_gateway.public_ip
}

output "tunnel_parameter_path" {
  description = "SSM Parameter Store path prefix holding the negotiated tunnel config for the Ansible vpn-gateway role."
  value       = var.tunnel_parameter_path
}

output "customer_gateway_configuration" {
  description = <<-EOT
    AWS-generated configuration XML for this specific VPN connection —
    the authoritative source for exact IKE/IPsec parameters (encryption,
    DH group, lifetimes), not the values ansible/roles/vpn-gateway's
    templates assume. Cross-check against this (`terragrunt output -raw
    customer_gateway_configuration`) before troubleshooting a tunnel that
    won't come up; AWS revises its recommended defaults over time.
  EOT
  value       = aws_vpn_connection.this.customer_gateway_configuration
  sensitive   = true
}
