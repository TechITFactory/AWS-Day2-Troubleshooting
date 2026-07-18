# Section 4 — Lab Setup (do this once)  (~8m)

---

## Lesson 4.1 — The two Terraform modules  [🎬 · ~3m]

Before we dive into the troubleshooting labs, we need to build the environment. Every lab will break something in this environment, and you'll diagnose and fix it. To make that repeatable — build once, break many times — we're using Terraform.

The entire NorthBank lab environment is built from two Terraform modules. Think of them as building blocks.

### Module 1: base-network — the foundation

This module creates NorthBank's VPC foundation. It's the network layer that everything else runs on.

What it creates:
- A `/16` VPC with DNS enabled
- **Two public subnets** and **two private subnets** across the first two availability zones in your region
- An Internet Gateway with a public route table that routes the default route to the IGW
- **One NAT Gateway** in a single AZ (we'll talk about why in a moment) with a private route table that routes the default route to the NAT
- Three core security groups that form a chain: `alb`, `app`, and `db`

The security group chain is critical. This is least privilege at the network layer:
- The `alb` security group allows port 80 from the internet
- The `app` security group allows port 80 **only from the ALB security group**
- The `db` security group allows port 3306 **only from the app security group**

So the traffic flow is: internet → load balancer → app servers → database. Each layer can only talk to the layer it needs. This chaining is exactly what several labs will break and you'll need to diagnose.

### Why one NAT Gateway?

In production, NorthBank would run one NAT Gateway per availability zone for high availability. If one AZ fails, the other keeps running. But each NAT Gateway costs about $32 per month plus data transfer charges.

For these labs, we're using one NAT Gateway to keep costs down. That's an honest ops trade-off: resilience versus cost. We're in a sandbox learning environment, so we optimize for cost. In production, you'd optimize for availability.

### Module 2: web-app — the application tier

This module creates the NorthBank digital banking application. This is the system most labs will break.

What it creates:
- An **Application Load Balancer** in the public subnets with an HTTP listener on port 80 pointing to a target group
- A **launch template** that defines the instance configuration: Amazon Linux 2023, IMDSv2 required, an instance role with permissions for Systems Manager and CloudWatch, and a user data script that installs and starts nginx
- An **Auto Scaling group** in the private subnets running that launch template, with a minimum of 2 instances, desired 2, maximum 4
- A **target group** with a health check on `/health` — this is what the load balancer uses to decide if instances are healthy
- An **optional RDS MySQL database** that's off by default. We only turn it on for the labs that need it.

### Key design decisions

**ELB health-check type** — the Auto Scaling group is configured to use the load balancer's health checks instead of EC2 status checks. This means the load balancer's opinion of "healthy" drives instance replacement. If the load balancer marks an instance as unhealthy, the Auto Scaling group will terminate it and launch a new one. Labs 7 and 8 explore exactly this behavior.

**IMDSv2 required** — the launch template requires Instance Metadata Service version 2. This is a security best practice that pre-empts a common Security Hub finding. We ship the configuration correct so we can talk about the finding in Lab 13 rather than accidentally trip it.

**SSM instance role, no SSH** — the instances have a role that allows Systems Manager access, and there are no SSH keys. This is how modern ops manages fleets. You don't SSH to individual instances. You use Systems Manager Session Manager for interactive access and Systems Manager Run Command or Patch Manager for automation. Lab 12 on patching relies on this.

**RDS off by default** — a running RDS instance, even a `db.t3.micro`, costs real money 24/7. Storage costs add up. So the database is off by default. You'll turn it on only for labs 9, 11, and 15, then turn it off immediately after. This keeps the lab bill manageable.

---

## Lesson 4.2 — Deploy the sandbox environment  [🧪 · ~4m]

The `envs/sandbox` directory is a Terraform root that wires both modules together. You'll apply it once, and then each lab's break script will break part of it.

### Step 1: Initialize Terraform

```bash
cd envs/sandbox
terraform init
```

This downloads the AWS provider and sets up the backend. It takes about 10 seconds.

### Step 2: Apply the configuration

```bash
terraform apply
```

Review the plan. You'll see it's creating a VPC, subnets, route tables, an Internet Gateway, a NAT Gateway, security groups, a load balancer, a target group, a launch template, an Auto Scaling group, and IAM roles.

Type `yes` to confirm. The apply takes about 3 to 5 minutes. The load balancer is the slowest part — it takes a couple of minutes to provision.

### Step 3: Read the outputs

Once the apply completes, read the outputs:

```bash
terraform output
```

You'll see a list of values like:
- `app_url` — the HTTP URL to the load balancer. This is what you'll open in a browser.
- `asg_name` — the Auto Scaling group name. Many labs will reference this.
- `alb_arn` — the load balancer ARN.
- `target_group_arn` — the target group ARN.
- `vpc_id`, `instance_role_name`, and many others.

The labs read these values programmatically. For example, a break script might run:

```bash
terraform -chdir=../../envs/sandbox output -raw asg_name
```

This lets the break scripts be portable. They don't hardcode resource names.

### Step 4: Verify the app is working

Copy the `app_url` from the outputs and open it in a browser. You should see the NorthBank banking page. It's a simple static page served by nginx. The page says "NorthBank Digital Banking" and has a login form.

If the page loads, the environment is working. The load balancer can reach the instances, the instances are healthy, and the security groups are allowing traffic.

If the page doesn't load, wait another minute. The Auto Scaling group launches instances, then the load balancer health checks take 30 seconds to mark them healthy. Give it a full minute after the terraform apply completes, then refresh.

---

## Lesson 4.3 — Cost controls & teardown (READ THIS)  [📄 · ~1m]

This is critical. These labs are designed to run in a **sandbox account only**. The break scripts deliberately break things. Never point this at a real account with production workloads or important data.

### Cost breakdown

While the environment is running, you're paying for:
- Application Load Balancer: roughly $0.023 per hour plus load balancer capacity units (LCUs) based on traffic. Minimal traffic means minimal LCUs. About $17 per month if left running.
- Two t3.micro instances: roughly $0.01 per hour each. About $15 per month total.
- One NAT Gateway: roughly $0.045 per hour plus data transfer charges. About $32 per month.
- RDS MySQL (when enabled): a db.t3.micro is roughly $0.02 per hour, plus storage at $0.115 per GB-month. About $15-20 per month if left running with minimal storage.

Total: roughly $80-100 per month if you leave everything running. That's the worst case.

The right way to use this: **build it, do a lab, tear it down**. A three-hour lab session costs a few dollars, not $100.

### The database toggle

The database is off by default. Turn it on only for labs 9, 11, and 15:

```bash
terraform apply -var="create_database=true"
```

Do the lab. Then immediately turn it off:

```bash
terraform apply -var="create_database=false"
```

This destroys the RDS instance and stops the charges. Labs that don't need the database won't have it running.

### Tear down after each session

When you're done for the day, destroy the environment:

```bash
terraform destroy
```

Review the plan, type `yes`. It takes about 2-3 minutes. This removes the load balancer, the Auto Scaling group, the instances, the NAT Gateway, the subnets, the VPC — everything. You pay for zero resources while the environment is destroyed.

The next time you want to do a lab, you run `terraform apply` again. It rebuilds the environment from scratch in 3-5 minutes. Same configuration, same resource names, clean slate.

### Set a budget alarm

Before you start the labs, set a budget alarm. Go to AWS Billing, create a budget for $10 or $20 per month, and configure an alarm to email you if you exceed 80% of the budget.

This is your safety net. If you forget to run `terraform destroy` and leave the environment running for a week, the alarm will page you. Section 14 (the cost lab) shows you how to set this up. Do it now, before you forget.

### Finding leftovers

Everything the Terraform creates is tagged with `Project=NorthBank`. If you suspect something didn't get destroyed, you can search for leftovers:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=NorthBank \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table
```

This lists every resource in your account with that tag. If the list is empty after a `terraform destroy`, you're clean. If it's not empty, something got left behind — investigate and clean it up manually.

### The safety rules

To summarize:
1. **Sandbox account only.** Never run this in a real account.
2. **Destroy after each session.** `terraform destroy` when you're done.
3. **Database on only when needed.** Labs 9, 11, 15 — then off immediately.
4. **Set a budget alarm.** $10-20 per month, 80% threshold. Do it now.
5. **Check for leftovers.** Use the tag search if you're unsure.

Follow these rules and the labs will cost a few dollars per month, not $100. Ignore them and you'll get a surprise bill.

---

You're now ready. The environment is built, you know the two modules, you know how to tear it down, and you know the cost controls. Let's start breaking things.
