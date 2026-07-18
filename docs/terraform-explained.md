# Terraform Explained — what `envs/sandbox` actually deploys

> Plain-English notes on **every `.tf` file** used to build the lab environment. No Terraform
> experience needed. Read this once and you'll know exactly what shows up in your AWS account when
> you run `terraform apply`.

---

## The big picture (read this first)

When you run `terraform apply` in `envs/sandbox`, you build a small but realistic banking web app:

```
        Internet
           │
           ▼
   ┌─────────────────┐   public subnets
   │  Load Balancer  │   (reachable from the internet)
   └────────┬────────┘
            │  port 80, only to the app
            ▼
   ┌─────────────────┐   private subnets
   │  2 web servers  │   (EC2 in an Auto Scaling group, running nginx)
   │  (Auto Scaling) │
   └────────┬────────┘
            │  port 3306, only to the DB
            ▼
   ┌─────────────────┐   private subnets
   │  MySQL database │   (RDS — OPTIONAL, off by default)
   └─────────────────┘
```

Three layers, each only allowed to talk to the next: **internet → load balancer → web servers →
database**. That chain is the thing most labs break and you fix.

It's built from **two reusable modules** wired together by one **root**:

| Piece | Folder | Job |
|-------|--------|-----|
| **Root** | `envs/sandbox/` | Ties the two modules together; you run Terraform here |
| **Module 1: network** | `modules/base-network/` | The VPC foundation (network + firewalls) |
| **Module 2: app** | `modules/web-app/` | The load balancer, web servers, and optional database |

> A **module** is just a reusable folder of Terraform. A **root** is the folder you actually run
> `terraform apply` in; it calls the modules and fills in their settings.

---

## Part 1 — `envs/sandbox/` (the root you run)

This is the only place you run Terraform. It doesn't create much itself — it **calls the two
modules** and passes settings between them.

### `main.tf` — the wiring

- **`terraform { … }`** — says which Terraform version and which providers are needed (the AWS
  provider v5+, i.e. the plugin that talks to AWS).
- **`provider "aws"`** — sets the AWS **region** and puts **default tags** on *everything* it
  creates: `Project=NorthBank`, `Env`, `ManagedBy=terraform`, `Course=aws-day2`. Those tags are how
  Lab 14 finds cost and how you hunt for leftovers.
- **`module "network"`** — calls `base-network` to build the VPC, subnets, and firewalls.
- **`module "app"`** — calls `web-app` to build the load balancer, web servers, and optional DB. It
  **feeds the network module's outputs in as inputs** (VPC id, subnet ids, the three security group
  ids), plus the instance size and the `create_database` on/off switch. This is how the two modules
  compose into one environment.

### `variables.tf` — the knobs you can turn

| Variable | Default | What it does |
|----------|---------|--------------|
| `region` | `us-east-1` | Which AWS region to build in |
| `name` | `northbank` | Name prefix on every resource |
| `environment` | `nonprod` | Environment label / tag (this is a sandbox, so nonprod) |
| `vpc_cidr` | `10.20.0.0/16` | The private IP range for the network |
| `instance_type` | `t3.micro` | Size of the web servers (kept small = cheap) |
| `create_database` | `false` | **The big cost switch.** `true` = also build the MySQL DB. Only turn on for labs 9, 11, 15, then turn off. |

### `outputs.tf` — the values the labs read

After `apply`, Terraform prints these. The labs' `break.sh` scripts read them with
`terraform -chdir=../../envs/sandbox output -raw <name>`, so **the names must stay stable**.

- `app_url` / `alb_dns_name` — the web address to open or curl.
- `alb_arn`, `target_group_arn`, `asg_name` — IDs the load-balancer / scaling labs poke at.
- `instance_role_name` — the web servers' IAM role (IAM + patching labs).
- `vpc_id`, `app_security_group_id`, `alb_security_group_id`, `db_security_group_id`,
  `private_route_table_id` — networking IDs.
- `db_instance_id`, `db_endpoint` — the database (or `null` when `create_database = false`).

---

## Part 2 — `modules/base-network/` (the network foundation)

This builds the **VPC** (your own private network in AWS) and the **firewalls**. Nothing here
serves the app — it's the ground everything else stands on.

### `main.tf` — what gets created

- **`data "aws_availability_zones"`** — looks up the region's data centers ("AZs") and picks the
  first two, so the app spans two AZs for resilience.
- **`aws_vpc`** — the private network itself (`10.20.0.0/16`), with DNS turned on.
- **`aws_subnet` (public ×2)** — two "public" sub-networks that *can* reach the internet. The load
  balancer lives here. `map_public_ip_on_launch = true` gives things here a public IP.
- **`aws_subnet` (private ×2)** — two "private" sub-networks with **no** direct internet access. The
  web servers and database live here, hidden from the internet.
- **`aws_internet_gateway`** — the door between the VPC and the internet (used by the public subnets).
- **`aws_route_table` (public) + `aws_route`** — a signpost that sends public-subnet traffic to the
  internet gateway.
- **`aws_eip` + `aws_nat_gateway`** — the **NAT Gateway** lets the *private* servers reach the
  internet **outbound only** (to download patches, talk to AWS services), without letting the
  internet reach *them*. It needs a fixed public IP (the EIP). **This is the main hourly cost** in
  the network — we run just **one** (not one per AZ) to save money.
- **`aws_route_table` (private) + `aws_route` (via NAT)** — sends private-subnet outbound traffic
  through the NAT Gateway. (Labs 4/6 can turn NAT off to simulate "servers lost internet.")
- **The three security groups** — these are the firewalls, and the chain is the whole point:
  - **`alb` SG** — allows HTTP (port 80) **from the internet**. Attached to the load balancer.
  - **`app` SG** — allows port 80 **only from the ALB security group** (not the internet).
    *Lab 6 breaks this rule so "healthy servers go unhealthy."*
  - **`db` SG** — allows MySQL (port 3306) **only from the app security group**.
    *Lab 9 breaks this so "the app can't reach the database."*

> **Security group = a firewall around a resource.** "Allow from the ALB security group" means "only
> the load balancer can knock on this port" — much safer than opening it to the whole internet.

### `variables.tf` — the knobs

| Variable | Default | What it does |
|----------|---------|--------------|
| `name` | `northbank` | Name prefix |
| `environment` | `nonprod` | Env tag |
| `vpc_cidr` | `10.20.0.0/16` | The network's IP range |
| `enable_nat_gateway` | `true` | Turn the NAT Gateway on/off (labs 4/6 turn it off to break internet access) |
| `tags` | `{}` | Extra tags to add |

### `outputs.tf` — what it hands to the app module

`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, the three security group IDs
(`alb`/`app`/`db`), `nat_gateway_id`, and `private_route_table_id`. The `web-app` module and the
labs' `break.sh` scripts consume these.

---

## Part 3 — `modules/web-app/` (the application)

This builds the actual app: a **load balancer**, a **group of web servers**, and an **optional
database**. This is the layer most labs break.

### `main.tf` — what gets created

**Finding the server image**
- **`data "aws_ssm_parameter" "al2023_ami"`** — asks AWS for the latest Amazon Linux 2023 image, so
  the servers always boot a current OS (with the SSM agent built in, needed for Lab 12 patching).

**Permissions for the servers (IAM)**
- **`aws_iam_role` + `aws_iam_instance_profile`** — the identity the web servers run as.
- **Two policy attachments** — `AmazonSSMManagedInstanceCore` (lets you manage/patch/get-a-shell
  without SSH — Labs 4 & 12) and `CloudWatchAgentServerPolicy` (lets them push logs/metrics — Labs
  2 & 3).

**The web servers (compute)**
- **`aws_launch_template`** — the "recipe" for each web server: which image, which size
  (`t3.micro`), which security group (`app`), the startup script (`user-data.sh`, which installs
  nginx), and **IMDSv2 required** (a security best-practice that avoids a Lab 13 finding).
- **`aws_autoscaling_group`** — runs 2 web servers (min 2 / desired 2 / max 4) across the private
  subnets, and **replaces any that go unhealthy**. `health_check_type = "ELB"` means the *load
  balancer's* opinion decides health — central to Labs 7 & 8.

**The load balancer (traffic)**
- **`aws_lb`** — the internet-facing Application Load Balancer, in the public subnets, using the
  `alb` security group.
- **`aws_lb_target_group`** — the pool the load balancer sends traffic to. Its **health check hits
  `/health` and expects a `200`** — Labs 7 & 15 break this on purpose.
- **`aws_lb_listener`** — says "listen on port 80 and forward to the target group."

**The database (optional — only when `create_database = true`)**
- **`random_password`** — generates a strong DB password.
- **`aws_db_subnet_group`** — tells RDS which (private) subnets to use.
- **`aws_db_instance`** — the MySQL database: `db.t3.micro`, encrypted, **single-AZ** (cheaper;
  labs discuss the prod trade-off), **not public**, using the `db` security group. `skip_final_snapshot = true`
  is a sandbox convenience (never do that in real prod).

### `variables.tf` — the knobs

| Variable | Default | What it does |
|----------|---------|--------------|
| `name`, `environment` | — | Naming / tagging |
| `vpc_id`, `*_subnet_ids`, `*_security_group_id` | — | **Fed in from base-network** (that's how the modules connect) |
| `instance_type` | `t3.micro` | Web server size |
| `min_size` / `desired_capacity` / `max_size` | 2 / 2 / 4 | How many web servers |
| `health_check_path` | `/health` | The page the load balancer checks |
| `create_database` | `false` | Build the MySQL DB or not |
| `db_instance_class` | `db.t3.micro` | Database size |
| `db_engine_version` | `8.0` | MySQL version |
| `db_backup_retention_days` | `7` | Days of automated backups (`0` = disabled — a Lab 11 talking point) |

### `outputs.tf` — the values it exposes

`alb_dns_name`, `alb_arn`, `target_group_arn`, `asg_name`, `launch_template_id`,
`instance_role_name`, and (when the DB is on) `db_instance_id`, `db_endpoint`. The root re-exposes
these so the labs can read them.

### `user-data.sh` (not `.tf`, but part of the deploy)

The startup script each web server runs on first boot: it installs **nginx**, serves a simple
NorthBank banking page at `/`, and a tiny `/health` page that returns `OK` (that's what the load
balancer's health check looks for).

---

## Quick reference — everything `apply` creates

**Always (base, no DB):**
- 1 VPC, 2 public + 2 private subnets, 1 internet gateway, 1 NAT gateway (+1 EIP), 2 route tables
- 3 security groups (alb / app / db) with their rules
- 1 IAM role + instance profile (+2 policy attachments)
- 1 launch template, 1 Auto Scaling group (2× `t3.micro` web servers)
- 1 Application Load Balancer, 1 target group, 1 listener

**Only when `create_database = true` (labs 9, 11, 15):**
- 1 RDS MySQL instance (`db.t3.micro`), 1 DB subnet group, 1 generated password

## Cost & safety reminders
- **Sandbox account only** — the labs deliberately break this.
- The **NAT Gateway** and, when on, the **RDS database** are the biggest costs. Turn the DB off
  right after the labs that need it.
- Tear it all down with `terraform -chdir=envs/sandbox destroy`.
- Full cost table + teardown: [`envs/sandbox/README.md`](../envs/sandbox/README.md) and
  [`labs/00-prerequisites/README.md`](../labs/00-prerequisites/README.md).
