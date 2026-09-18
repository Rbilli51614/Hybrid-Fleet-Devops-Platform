output "instance_id" {
  description = "Nexus instance ID — target this for SSM Session Manager access."
  value       = aws_instance.nexus.id
}

output "private_ip" {
  description = "Nexus instance's private IP."
  value       = aws_network_interface.nexus.private_ip
}

output "dns_name" {
  description = "DNS name Nexus is reachable at, if route53_zone_id was set; otherwise null."
  value       = var.route53_zone_id != null ? var.dns_record_name : null
}

output "backup_bucket_name" {
  description = "S3 bucket ansible/roles/nexus's backup script uploads to."
  value       = aws_s3_bucket.backups.bucket
}

output "data_volume_id" {
  description = "EBS volume ID holding Nexus's blob store. prevent_destroy = true — see this module's README before attempting to tear it down."
  value       = aws_ebs_volume.nexus_data.id
}
