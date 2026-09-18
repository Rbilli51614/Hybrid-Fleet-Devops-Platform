# vpc

Shared VPC module: public + private subnets across N AZs, one Internet Gateway, one (or per-AZ) NAT Gateway, and EKS/Karpenter/ALB auto-discovery tags when `eks_cluster_name` is set.

Versioned via git tags (`modules/vpc/vX.Y.Z`) and consumed by both the cloud-tier and "on-prem"-tier stacks under `terraform/live/**` — see [`../../../docs/architecture.md`](../../../docs/architecture.md#module-registry-convention).

## Example

```hcl
module "cloud_vpc" {
  source = "git::https://github.com/Rbilli51614/Hybrid-Fleet-Devops-Platform.git//terraform/modules/vpc?ref=modules/vpc/v1.0.0"

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
