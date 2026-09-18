locals {
  join_token_ssm_path = coalesce(var.join_token_ssm_path, "/${var.cluster_name}/join-command")
}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Networking: no inbound path from outside the group, no SSH, no public IPs.
# Access is Session Manager only (see IAM below) — see docs/decision-stack.md
# on why SSM replaces SSH/bastion for this tier.
# ---------------------------------------------------------------------------

resource "aws_security_group" "nodes" {
  name        = "${var.name}-nodes"
  description = "Self-managed Kubernetes node traffic (control plane <-> workers). No ingress from outside the group; no SSH."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-nodes"
  })
}

resource "aws_vpc_security_group_ingress_rule" "self_all" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All traffic between VM-tier nodes: kube-apiserver, etcd, kubelet, CNI overlay, NodePort range, etc."
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.nodes.id
  description       = "Outbound for package/container image pulls via the on-prem VPC's NAT gateway, and SSM/API calls."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# S3 staging bucket for the Ansible `community.aws.aws_ssm` connection
# plugin. It uses S3 as an intermediary for command output/file transfer
# over the Session Manager channel — both the operator's machine and the
# target instance need access, hence granting the node IAM roles below.
# Objects are transient (command output), so a short expiry is enough.
# ---------------------------------------------------------------------------

resource "random_id" "ssm_transfer_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "ssm_transfer" {
  bucket = "${var.name}-ssm-transfer-${random_id.ssm_transfer_bucket_suffix.hex}"

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    id     = "expire-transient-transfer-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }
  }
}

data "aws_iam_policy_document" "ssm_transfer_bucket" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:GetEncryptionConfiguration",
    ]
    resources = ["${aws_s3_bucket.ssm_transfer.arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ssm_transfer.arn]
  }
}

resource "aws_iam_role_policy" "ssm_transfer_bucket" {
  for_each = var.node_groups

  name   = "${var.name}-${each.key}-ssm-transfer-bucket"
  role   = aws_iam_role.node[each.key].id
  policy = data.aws_iam_policy_document.ssm_transfer_bucket.json
}

# ---------------------------------------------------------------------------
# IAM — SSM Session Manager access, plus the minimum needed to exchange the
# kubeadm join command over SSM Parameter Store. No SSH keys anywhere.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  ssm_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.join_token_ssm_path}"

  ssm_parameter_actions_by_role = {
    control-plane = ["ssm:PutParameter", "ssm:GetParameter"]
    worker        = ["ssm:GetParameter"]
  }
}

resource "aws_iam_role" "node" {
  for_each = var.node_groups

  name               = "${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  for_each = var.node_groups

  role       = aws_iam_role.node[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "join_token_parameter" {
  for_each = var.node_groups

  statement {
    actions   = lookup(local.ssm_parameter_actions_by_role, each.value.role, ["ssm:GetParameter"])
    resources = [local.ssm_parameter_arn]
  }
}

resource "aws_iam_role_policy" "join_token_parameter" {
  for_each = var.node_groups

  name   = "${var.name}-${each.key}-join-token-parameter"
  role   = aws_iam_role.node[each.key].id
  policy = data.aws_iam_policy_document.join_token_parameter[each.key].json
}

resource "aws_iam_instance_profile" "node" {
  for_each = var.node_groups

  name = "${var.name}-${each.key}"
  role = aws_iam_role.node[each.key].name
}

# ---------------------------------------------------------------------------
# Launch templates + Auto Scaling Groups
#
# Terraform's job stops at "the box exists, is reachable via SSM, and has
# an IAM role" — kubeadm/containerd installation and cluster bootstrap is
# Ansible's job (ansible/playbooks/bootstrap-k8s.yml), run over the SSM
# connection plugin, not baked into user_data. Keeps the IaC/config-mgmt
# boundary clean, per docs/jd-mapping.md.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix   = "${var.name}-${each.key}-"
  image_id      = data.aws_ssm_parameter.ami.value
  instance_type = each.value.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.node[each.key].name
  }

  vpc_security_group_ids = [aws_security_group.nodes.id]

  # No key_name: SSH is not part of this tier's access model.

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = each.value.root_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name                      = "${var.name}-${each.key}"
      Role                      = each.value.role
      "hybrid-fleet.io/cluster" = var.cluster_name
    })
  }

  tags = var.tags
}

resource "aws_autoscaling_group" "node" {
  for_each = var.node_groups

  name = "${var.name}-${each.key}"

  desired_capacity = each.value.desired_size
  min_size         = each.value.min_size
  max_size         = each.value.max_size

  vpc_zone_identifier = var.subnet_ids
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(var.tags, {
      Name                      = "${var.name}-${each.key}"
      Role                      = each.value.role
      "hybrid-fleet.io/cluster" = var.cluster_name
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
