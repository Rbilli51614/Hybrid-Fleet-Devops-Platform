output "zone_id" {
  description = "Hosted zone ID, for creating records against it."
  value       = aws_route53_zone.private.zone_id
}

output "zone_name" {
  description = "Hosted zone name."
  value       = aws_route53_zone.private.name
}
