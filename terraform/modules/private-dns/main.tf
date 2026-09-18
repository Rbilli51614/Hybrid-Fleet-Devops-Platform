resource "aws_route53_zone" "private" {
  name = var.zone_name

  vpc {
    vpc_id = var.primary_vpc_id
  }

  tags = var.tags

  lifecycle {
    # Additional associations (aws_route53_zone_association below) show up
    # in the zone's VPC list on refresh; without this, Terraform would try
    # to "correct" that list back down to just the primary VPC every plan.
    ignore_changes = [vpc]
  }
}

resource "aws_route53_zone_association" "additional" {
  for_each = toset(var.additional_vpc_ids)

  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = each.value
}
