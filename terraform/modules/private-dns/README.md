# private-dns

A Route 53 private hosted zone, associated with both the cloud and on-prem VPCs so either tier resolves the same internal names — the "shared identity" piece of the traffic layer in [`docs/architecture.md`](../../../docs/architecture.md).

Versioned via git tags (`modules/private-dns/vX.Y.Z`) — see [module registry convention](../../../docs/architecture.md#module-registry-convention).

## Example

```hcl
module "private_dns" {
  source = "git::https://github.com/<org>/Hybrid-Fleet-Devops-Platform.git//terraform/modules/private-dns?ref=modules/private-dns/v1.0.0"

  zone_name           = "hybrid-fleet.internal"
  primary_vpc_id      = module.cloud_vpc.vpc_id
  additional_vpc_ids  = [module.onprem_vpc.vpc_id]
}
```

| Name | Description | Type | Default |
|---|---|---|---|
| `zone_name` | Private hosted zone name | `string` | — |
| `primary_vpc_id` | VPC the zone is created against | `string` | — |
| `additional_vpc_ids` | Further VPCs to associate | `list(string)` | `[]` |
| `tags` | Extra tags on the zone | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `zone_id` | For creating records against the zone |
| `zone_name` | Zone name |
