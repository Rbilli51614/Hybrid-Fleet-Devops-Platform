data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# AWS side: a real Virtual Private Gateway attached to the cloud VPC. This
# is the managed half of the tunnel — no different from what you'd deploy
# against an actual on-prem router. See docs/decision-stack.md for why a
# VPN Gateway (not Transit Gateway/Direct Connect) at this scale.
# ---------------------------------------------------------------------------

resource "aws_vpn_gateway" "cloud" {
  vpc_id          = var.cloud_vpc_id
  amazon_side_asn = var.amazon_side_asn

  tags = merge(var.tags, {
    Name = "${var.name}-vgw"
  })
}

resource "aws_vpn_gateway_route_propagation" "cloud" {
  for_each = toset(var.cloud_private_route_table_ids)

  vpn_gateway_id = aws_vpn_gateway.cloud.id
  route_table_id = each.value
}

# ---------------------------------------------------------------------------
# "Customer" side: a self-managed strongSwan instance in the on-prem VPC's
# public subnet, standing in for the physical router/firewall a real DC
# interconnect would terminate at. Static ENI (source/dest check disabled)
# + Elastic IP, so it has a stable address for the Customer Gateway and can
# route on-prem-VPC-bound tunnel traffic like a real router would.
# ---------------------------------------------------------------------------

resource "aws_security_group" "onprem_gateway" {
  name        = "${var.name}-onprem-gateway"
  description = "IPsec tunnel endpoint for the simulated on-prem side of the Site-to-Site VPN."
  vpc_id      = var.onprem_vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-onprem-gateway"
  })
}

# Scoped to AWS's own two tunnel endpoint IPs, not 0.0.0.0/0 — known only
# after the VPN connection below is created. Deliberately four singleton
# resources, not a for_each over [tunnel1_address, tunnel2_address]: those
# addresses aren't known until aws_vpn_connection is actually created, and
# for_each's key set (unlike a single resource's attribute) must be known
# at plan time — a for_each here would fail on every first apply.
resource "aws_vpc_security_group_ingress_rule" "ike_tunnel1" {
  security_group_id = aws_security_group.onprem_gateway.id
  description       = "IKE (UDP 500) from AWS VPN tunnel 1 endpoint"
  cidr_ipv4         = "${aws_vpn_connection.this.tunnel1_address}/32"
  from_port         = 500
  to_port           = 500
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "ike_tunnel2" {
  security_group_id = aws_security_group.onprem_gateway.id
  description       = "IKE (UDP 500) from AWS VPN tunnel 2 endpoint"
  cidr_ipv4         = "${aws_vpn_connection.this.tunnel2_address}/32"
  from_port         = 500
  to_port           = 500
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "nat_t_tunnel1" {
  security_group_id = aws_security_group.onprem_gateway.id
  description       = "IPsec NAT-T (UDP 4500) from AWS VPN tunnel 1 endpoint"
  cidr_ipv4         = "${aws_vpn_connection.this.tunnel1_address}/32"
  from_port         = 4500
  to_port           = 4500
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "nat_t_tunnel2" {
  security_group_id = aws_security_group.onprem_gateway.id
  description       = "IPsec NAT-T (UDP 4500) from AWS VPN tunnel 2 endpoint"
  cidr_ipv4         = "${aws_vpn_connection.this.tunnel2_address}/32"
  from_port         = 4500
  to_port           = 4500
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.onprem_gateway.id
  description       = "Outbound to the tunnel, package installs, and SSM/API calls."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_network_interface" "onprem_gateway" {
  subnet_id       = var.onprem_public_subnet_id
  security_groups = [aws_security_group.onprem_gateway.id]

  # Required for this instance to route traffic that isn't addressed to
  # itself (i.e. to actually act as a router for the tunnel).
  source_dest_check = false

  tags = merge(var.tags, {
    Name = "${var.name}-onprem-gateway"
  })
}

resource "aws_eip" "onprem_gateway" {
  domain            = "vpc"
  network_interface = aws_network_interface.onprem_gateway.id

  tags = merge(var.tags, {
    Name = "${var.name}-onprem-gateway"
  })
}

# ---------------------------------------------------------------------------
# The VPN connection itself: static routing (no BGP) — simplest correct
# choice at this scale; see docs/pitfalls.md for when that stops being true.
# ---------------------------------------------------------------------------

resource "aws_customer_gateway" "onprem" {
  bgp_asn    = var.customer_side_asn
  ip_address = aws_eip.onprem_gateway.public_ip
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name = "${var.name}-onprem-cgw"
  })
}

resource "aws_vpn_connection" "this" {
  vpn_gateway_id      = aws_vpn_gateway.cloud.id
  customer_gateway_id = aws_customer_gateway.onprem.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpn"
  })
}

resource "aws_vpn_connection_route" "onprem_cidr" {
  vpn_connection_id      = aws_vpn_connection.this.id
  destination_cidr_block = var.onprem_vpc_cidr
}

resource "aws_route" "onprem_to_cloud" {
  for_each = toset(var.onprem_private_route_table_ids)

  route_table_id         = each.value
  destination_cidr_block = var.cloud_vpc_cidr
  network_interface_id   = aws_network_interface.onprem_gateway.id
}

# ---------------------------------------------------------------------------
# Hand the negotiated tunnel details to Ansible via SSM Parameter Store —
# same "Terraform provisions/writes, Ansible configures/reads" split used
# for the kubeadm join command in terraform/modules/vm-k8s-asg. No
# chicken-and-egg here (unlike that case): Terraform already knows these
# values the moment aws_vpn_connection is created, so it writes them
# directly rather than waiting on anything the instance itself produces.
# ---------------------------------------------------------------------------

locals {
  tunnel_parameters = {
    "${var.tunnel_parameter_path}/onprem-cidr"             = var.onprem_vpc_cidr
    "${var.tunnel_parameter_path}/cloud-cidr"              = var.cloud_vpc_cidr
    "${var.tunnel_parameter_path}/tunnel1/outside-address" = aws_vpn_connection.this.tunnel1_address
    "${var.tunnel_parameter_path}/tunnel1/inside-cidr"     = aws_vpn_connection.this.tunnel1_cgw_inside_address != "" ? "${aws_vpn_connection.this.tunnel1_cgw_inside_address}/30" : ""
    "${var.tunnel_parameter_path}/tunnel2/outside-address" = aws_vpn_connection.this.tunnel2_address
    "${var.tunnel_parameter_path}/tunnel2/inside-cidr"     = aws_vpn_connection.this.tunnel2_cgw_inside_address != "" ? "${aws_vpn_connection.this.tunnel2_cgw_inside_address}/30" : ""
  }

  tunnel_secure_parameters = {
    "${var.tunnel_parameter_path}/tunnel1/preshared-key" = aws_vpn_connection.this.tunnel1_preshared_key
    "${var.tunnel_parameter_path}/tunnel2/preshared-key" = aws_vpn_connection.this.tunnel2_preshared_key
  }
}

resource "aws_ssm_parameter" "tunnel_config" {
  for_each = local.tunnel_parameters

  name  = each.key
  type  = "String"
  value = each.value

  tags = var.tags
}

resource "aws_ssm_parameter" "tunnel_secrets" {
  for_each = local.tunnel_secure_parameters

  name  = each.key
  type  = "SecureString"
  value = each.value

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM: SSM Session Manager access, plus read-only access to the tunnel
# parameters above. No SSH — same access model as the rest of the VM tier.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "onprem_gateway" {
  name               = "${var.name}-onprem-gateway"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "onprem_gateway_ssm" {
  role       = aws_iam_role.onprem_gateway.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "tunnel_parameters_read" {
  statement {
    actions = ["ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.tunnel_parameter_path}/*",
    ]
  }
}

resource "aws_iam_role_policy" "tunnel_parameters_read" {
  name   = "${var.name}-onprem-gateway-tunnel-parameters"
  role   = aws_iam_role.onprem_gateway.id
  policy = data.aws_iam_policy_document.tunnel_parameters_read.json
}

resource "aws_iam_instance_profile" "onprem_gateway" {
  name = "${var.name}-onprem-gateway"
  role = aws_iam_role.onprem_gateway.name
}

resource "aws_instance" "onprem_gateway" {
  ami                  = data.aws_ssm_parameter.ami.value
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.onprem_gateway.name

  network_interface {
    network_interface_id = aws_network_interface.onprem_gateway.id
    device_index         = 0
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # No key_name: SSH is not part of this instance's access model either —
  # config happens over SSM (ansible/roles/vpn-gateway), same as the rest
  # of the VM tier.

  tags = merge(var.tags, {
    Name                      = "${var.name}-onprem-gateway"
    Role                      = "vpn-gateway"
    "hybrid-fleet.io/cluster" = var.name
  })
}
