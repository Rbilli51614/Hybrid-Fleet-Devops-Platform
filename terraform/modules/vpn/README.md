# vpn

A real AWS Site-to-Site VPN linking the cloud and on-prem VPCs — a Virtual Private Gateway on the cloud side, and a self-managed strongSwan instance (Elastic IP, no SSH — SSM only) standing in for a physical on-prem router on the other. Static routing, not BGP — see [`docs/decision-stack.md`](../../../docs/decision-stack.md) for why, and [`docs/pitfalls.md`](../../../docs/pitfalls.md) for when that stops being the right call.

Versioned via git tags (`modules/vpn/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

Terraform's job stops at "the tunnel is negotiated and its details are in SSM Parameter Store" — actually configuring strongSwan on the on-prem gateway instance is [`ansible/roles/vpn-gateway`](../../../ansible/roles/vpn-gateway/), same IaC/config-mgmt split as the rest of the VM tier (see [`docs/architecture.md`](../../../docs/architecture.md#the-vm-tier-same-iacconfig-mgmt-split-a-different-mechanism)).

## What actually happens

1. This module creates a Virtual Private Gateway attached to the cloud VPC, an Elastic IP + network interface for a "customer gateway" instance in the on-prem VPC's public subnet, an `aws_customer_gateway` pointed at that EIP, and an `aws_vpn_connection` between them.
2. AWS negotiates two tunnels (for redundancy) and returns their outside addresses, inside `/30` CIDRs, and pre-shared keys. This module writes all of that to SSM Parameter Store under `var.tunnel_parameter_path` (PSKs as `SecureString`) — the on-prem gateway instance's IAM role can read only that path.
3. `ansible/roles/vpn-gateway` (run over SSM, not SSH) reads those parameters and renders a strongSwan `ipsec.conf`/`ipsec.secrets`, enables IP forwarding, and brings the tunnels up.
4. Route propagation (`aws_vpn_gateway_route_propagation`) pushes the on-prem CIDR into the cloud VPC's private route tables automatically; on the on-prem side, this module adds an explicit route for the cloud CIDR via the gateway instance's network interface (which has `source_dest_check = false`, so it can actually route for other on-prem-VPC hosts).

## A real Terraform gotcha this module works around

The security group rules scoping IKE (UDP 500) and NAT-T (UDP 4500) inbound to AWS's own two tunnel endpoint IPs *look* like a natural `for_each` over `[tunnel1_address, tunnel2_address]` — but those addresses aren't known until `aws_vpn_connection` is actually created, and `for_each`'s key set (unlike a single resource's attribute value) has to be known at plan time. A `for_each` there fails on every first apply with "Invalid for_each argument." Four singleton resources (`ike_tunnel1`/`ike_tunnel2`/`nat_t_tunnel1`/`nat_t_tunnel2`) instead — each resource's own attributes are allowed to be "known after apply."

## Example

```hcl
module "vpn" {
  source = "git::https://github.com/<org>/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vpn?ref=modules/vpn/v1.0.0"

  name    = "hybrid-fleet"
  cloud_vpc_id                  = module.cloud_vpc.vpc_id
  cloud_vpc_cidr                 = "10.0.0.0/16"
  cloud_private_route_table_ids  = module.cloud_vpc.private_route_table_ids

  onprem_vpc_id                   = module.onprem_vpc.vpc_id
  onprem_vpc_cidr                  = "10.1.0.0/16"
  onprem_public_subnet_id          = module.onprem_vpc.public_subnet_ids[0]
  onprem_private_route_table_ids   = module.onprem_vpc.private_route_table_ids

  tunnel_parameter_path = "/hybrid-fleet/vpn"
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — |
| `cloud_vpc_id` / `cloud_vpc_cidr` | Cloud VPC and its CIDR | `string` | — |
| `cloud_private_route_table_ids` | Cloud VPC private route tables to propagate the on-prem CIDR into | `list(string)` | — |
| `onprem_vpc_id` / `onprem_vpc_cidr` | On-prem VPC and its CIDR | `string` | — |
| `onprem_public_subnet_id` | Public subnet for the on-prem gateway instance | `string` | — |
| `onprem_private_route_table_ids` | On-prem VPC private route tables to route the cloud CIDR into | `list(string)` | — |
| `ami_ssm_parameter` | SSM path resolving to the gateway instance's AMI | `string` | latest Ubuntu 22.04 LTS |
| `instance_type` | Gateway instance size | `string` | `"t3.micro"` |
| `amazon_side_asn` / `customer_side_asn` | BGP ASNs (unused — static routing) required by the underlying resources | `number` | `64512` / `65000` |
| `tunnel_parameter_path` | SSM path prefix for tunnel config exchange with Ansible | `string` | — (required) |
| `tags` | Extra tags applied to all resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `vpn_gateway_id` / `vpn_connection_id` | For reference/debugging in the AWS console |
| `onprem_gateway_instance_id` | Target this for SSM Session Manager access |
| `onprem_gateway_public_ip` | The Customer Gateway's `ip_address` |
| `tunnel_parameter_path` | For wiring into the Ansible playbook |

## Known limitation

The on-prem gateway is a single instance, not an HA pair — if it's replaced (instance failure, AZ event), the tunnel drops until Ansible re-runs against the new instance and the strongSwan config is re-rendered from the same SSM parameters (nothing about the tunnel negotiation itself needs to change, since the Elastic IP re-attaches to whatever replaces the ENI). Acceptable for a portfolio-scale simulation of a DC interconnect; a real deployment would run two gateway instances across AZs, each with its own Customer Gateway/VPN connection, for actual HA.
