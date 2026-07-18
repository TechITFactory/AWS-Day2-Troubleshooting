# Module: `web-app`

NorthBank's digital-banking web tier — the application most labs break and diagnose. Composes
on top of [`base-network`](../base-network/).

## What it creates

- An **Application Load Balancer** in the public subnets (listener :80 → target group).
- A **launch template** (Amazon Linux 2023, IMDSv2 required, SSM + CloudWatch agent role) and an
  **Auto Scaling group** in the private subnets running nginx (see `user-data.sh`).
- A **target group** with a `/health` health check (labs 7/8 hinge on this).
- An **optional RDS MySQL** instance (`create_database = true`) for labs 9, 11 & 15.

## Why the design looks like this (teaching points)

- **ELB health-check type** on the ASG means the load balancer's opinion of "healthy" drives
  instance replacement — the exact behavior labs 7 (target health) and 8 (Auto Scaling) explore.
- **IMDSv2 required** pre-empts a common Security Hub finding (lab 13). We ship it correct so we
  can *talk about* the finding rather than accidentally trip it.
- **SSM instance role, no SSH** is how modern ops manages fleets — and it's what lab 12
  (patching with Systems Manager) needs.
- **RDS off by default** because a running db.t3.micro + storage is the biggest surprise on a lab
  bill. Turn it on only for the labs that need it, and `destroy` right after.

## Usage (composed with base-network)

```hcl
module "network" {
  source = "../../modules/base-network"
  name   = "northbank-nonprod"
}

module "app" {
  source = "../../modules/web-app"
  name   = "northbank-nonprod"

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_security_group_id = module.network.app_security_group_id
  db_security_group_id  = module.network.db_security_group_id

  # create_database = true   # for labs 9, 11 & 15
}

output "app_url" {
  value = "http://${module.app.alb_dns_name}"
}
```

## Key variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `instance_type` | `t3.micro` | Web tier size |
| `min/desired/max_size` | `2/2/4` | ASG bounds |
| `health_check_path` | `/health` | TG health check |
| `create_database` | `false` | Provision RDS MySQL (labs 9/11/15) |
| `db_instance_class` | `db.t3.micro` | RDS size |
| `db_backup_retention_days` | `1` | Set `0` to demo "backups disabled" (lab 11). Kept low because free-tier-restricted accounts reject higher values (confirmed by hand) |

## Outputs (consumed by labs' `break.sh`)

`alb_dns_name` · `alb_arn` · `target_group_arn` · `asg_name` · `launch_template_id` ·
`instance_role_name` · `db_instance_id` · `db_endpoint`

## Cost & teardown

ALB (~$0.023/hr + LCUs), 2× t3.micro, and — if enabled — RDS. **`terraform destroy` after each
lab.** With `create_database = true`, expect the db to dominate the bill; tear it down promptly.
