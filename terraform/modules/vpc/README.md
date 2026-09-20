# vpc

Shared VPC module: public + private subnets across N AZs, one Internet Gateway, one (or per-AZ) NAT Gateway, and EKS/Karpenter/ALB auto-discovery tags when `eks_cluster_name` is set.

Versioned via git tags (`modules/vpc/vX.Y.Z`) and consumed by both the cloud-tier and "on-prem"-tier stacks under `terraform/live/**` — see [`../../../docs/architecture.md`](../../../docs/architecture.md#module-registry-convention).

## Example

## A live `terragrunt plan` on `onprem-vpc`, done long after `vpn` was applied, planned to delete the VPN route

`private_route_table_ids` is deliberately documented above as "consumed by the `vpn` module for route propagation" — but the private route table's own default route used to be declared as an inline `route { }` block on `aws_route_table.private`, and an inline block is authoritative for a route table's *entire* route set. Any route another resource adds to that same table later — exactly what `vpn`'s own `aws_route.onprem_to_cloud` does — gets flagged for removal the next time *this* module's own state is planned, since as far as its inline block is concerned, that route was never supposed to exist. A real `terragrunt plan` against `onprem-vpc`, run well after the VPN was already live, showed exactly that: `0 to add, 1 to change, 0 to destroy` on the surface, but the diff itself was replacing the route list wholesale — dropping the live onprem→cloud route in the process. Applying it would have actually cut the tunnel's usable routing, not just touched Terraform state.

The cloud side never showed this because it uses real AWS VGW route propagation (`aws_vpn_gateway_route_propagation` in the `vpn` module) instead of a plain `aws_route` resource — propagated routes are specially excluded from `aws_route_table`'s inline-route diff, so they never looked like drift. A manually-managed `aws_route` resource targeting someone else's route table isn't afforded that same exclusion.

Fixed (v1.0.1) by converting the private route table's default route to its own standalone `aws_route` resource (`aws_route.private_default`), matching the pattern the `vpn` module already used correctly. Each route is now independently owned by its own resource, so nothing claims authority over routes it didn't create.

## Example

```hcl
module "cloud_vpc" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vpc?ref=modules/vpc/v1.0.1"

  name                  = "hybrid-fleet-cloud"
  cidr_block            = "10.0.0.0/16"
  azs                   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs   = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
  single_nat_gateway    = true
  eks_cluster_name      = "hybrid-fleet-eks"
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `name` | Name prefix for all resources | `string` | — |
| `cidr_block` | VPC CIDR block | `string` | — |
| `azs` | AZs to spread subnets across | `list(string)` | — |
| `public_subnet_cidrs` | Public subnet CIDRs, one per AZ | `list(string)` | — |
| `private_subnet_cidrs` | Private subnet CIDRs, one per AZ | `list(string)` | — |
| `single_nat_gateway` | Share one NAT Gateway instead of one per AZ | `bool` | `true` |
| `eks_cluster_name` | Tags subnets for EKS/Karpenter/ALB discovery | `string` | `null` |
| `tags` | Extra tags applied to all resources | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `vpc_id` | ID of the created VPC |
| `vpc_cidr_block` | CIDR block of the created VPC |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `nat_gateway_ids` | NAT Gateway ID(s) |
| `private_route_table_ids` | Private route table ID(s) — consumed by the `vpn` module for route propagation |
| `public_route_table_id` | The (single, shared) public route table ID |
