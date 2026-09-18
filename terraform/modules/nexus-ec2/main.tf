data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

data "aws_subnet" "this" {
  id = var.private_subnet_id
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

resource "aws_security_group" "nexus" {
  name        = "${var.name}-nexus"
  description = "Nexus repository access (port 8081) from both K8s tiers; no SSH."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-nexus"
  })
}

resource "aws_vpc_security_group_ingress_rule" "nexus_ui" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.nexus.id
  description       = "Nexus repository API/UI from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 8081
  to_port           = 8081
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.nexus.id
  description       = "Outbound for package installs, S3 backup uploads, and SSM/API calls."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_network_interface" "nexus" {
  subnet_id       = var.private_subnet_id
  security_groups = [aws_security_group.nexus.id]

  tags = merge(var.tags, {
    Name = "${var.name}-nexus"
  })
}

# ---------------------------------------------------------------------------
# Data volume
#
# Deliberately a standalone EBS volume + explicit attachment, not part of a
# launch template. Nexus's blob store must outlive any single instance
# replacement — the volume is never destroyed just because the instance is.
# ---------------------------------------------------------------------------

resource "aws_ebs_volume" "nexus_data" {
  availability_zone = data.aws_subnet.this.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = merge(var.tags, {
    Name = "${var.name}-nexus-data"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "nexus_data" {
  device_name = var.data_volume_device_name
  volume_id   = aws_ebs_volume.nexus_data.id
  instance_id = aws_instance.nexus.id
}

# ---------------------------------------------------------------------------
# S3 backup bucket
#
# Lifecycle rules per docs/decision-stack.md's Cost layer: Standard -> IA ->
# Glacier -> expire. ansible/roles/nexus's backup script uploads here with
# this instance's own IAM role.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "backups" {
  bucket = "${var.name}-nexus-backups-${data.aws_caller_identity.current.account_id}"

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "nexus-backup-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = var.backup_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.backup_transition_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.backup_expiration_days
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — SSM Session Manager access, plus read/write on the backup bucket
# only. No SSH — same access model as the rest of the VM tier.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nexus" {
  name               = "${var.name}-nexus"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "nexus_ssm" {
  role       = aws_iam_role.nexus.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "backup_bucket" {
  statement {
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }
}

resource "aws_iam_role_policy" "backup_bucket" {
  name   = "${var.name}-nexus-backup-bucket"
  role   = aws_iam_role.nexus.id
  policy = data.aws_iam_policy_document.backup_bucket.json
}

resource "aws_iam_instance_profile" "nexus" {
  name = "${var.name}-nexus"
  role = aws_iam_role.nexus.name
}

# ---------------------------------------------------------------------------
# Instance
#
# Terraform's job stops at "the box exists, has a data volume attached, and
# is SSM-reachable" — Java/Nexus install, data-volume mount, and the backup
# cron are ansible/roles/nexus's job, consistent with the rest of the
# repo's IaC/config-mgmt split.
# ---------------------------------------------------------------------------

resource "aws_instance" "nexus" {
  ami                  = data.aws_ssm_parameter.ami.value
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.nexus.name

  network_interface {
    network_interface_id = aws_network_interface.nexus.id
    device_index         = 0
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # No key_name: SSH is not part of this instance's access model — config
  # happens over SSM (ansible/roles/nexus), same as the rest of the VM tier.

  tags = merge(var.tags, {
    Name                      = "${var.name}-nexus"
    Role                      = "nexus"
    "hybrid-fleet.io/cluster" = var.name
  })
}

# ---------------------------------------------------------------------------
# Internal DNS
# ---------------------------------------------------------------------------

resource "aws_route53_record" "nexus" {
  count = var.route53_zone_id != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.dns_record_name
  type    = "A"
  ttl     = 300
  records = [aws_network_interface.nexus.private_ip]
}
