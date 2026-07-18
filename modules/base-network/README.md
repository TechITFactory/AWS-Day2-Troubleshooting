# Module: `base-network`

NorthBank's shared VPC foundation. Roughly half the labs `terraform apply` this first, then
layer `web-app` on top.

## What it creates

- A `/16` VPC with DNS enabled.
- **2 public** + **2 private** subnets across the first two AZs in the region.
- Internet Gateway + public route table (default route → IGW).
- **One** NAT Gateway (single-AZ, cost-conscious) + private route table (default route → NAT).
- Three core security groups the app relies on:
  - `alb` — 80 from the internet
  - `app` — 80 **from the ALB SG only**
  - `db` — 3306 **from the app SG only**

## Why the design looks like this (teaching points)

- **Public vs private subnets** = the internet-facing tier vs the protected tier. The bank's web
  servers and database must not be directly reachable from the internet.
- **SG chaining** (`internet → alb → app → db`) is least privilege at the network layer, and it's
  exactly what lab 6 breaks and lab 7 diagnoses.
- **One NAT Gateway** is a deliberate cost trade-off. In prod NorthBank would run one per AZ for
  resilience; here we save ~$32/mo/AZ. It's an honest ops trade-off.

## Usage

```hcl
module "network" {
  source      = "../../modules/base-network"
  name        = "northbank-nonprod"
  environment = "nonprod"
  vpc_cidr    = "10.20.0.0/16"
  # enable_nat_gateway = false   # labs 4/6: simulate lost outbound internet
}
```

## Key variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `name` | `northbank` | Name prefix on every resource |
| `environment` | `nonprod` | `Env` tag |
| `vpc_cidr` | `10.20.0.0/16` | VPC range; subnets are `/24`s off it |
| `enable_nat_gateway` | `true` | Toggle off to break private-subnet egress (labs 4/6) |
| `tags` | `{}` | Extra tags merged everywhere |

## Outputs (consumed by `web-app` and labs' `break.sh`)

`vpc_id` · `public_subnet_ids` · `private_subnet_ids` · `alb_security_group_id` ·
`app_security_group_id` · `db_security_group_id` · `nat_gateway_id` · `private_route_table_id`

## Cost & teardown

Main cost is the NAT Gateway (~$0.045/hr + data) and the EIP. **`terraform destroy` when the
lab is done.** Nothing here is free-tier-forever.
