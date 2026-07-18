# Lab 00 — Prerequisites & Environment Setup

```
Status:    Do this once, before Lab 01
Owner:     You
Applies to: every lab in this course
```

> Not a ticket — there's no fault to find here. This is the one-time setup every other lab
> assumes is already done. Go through it top to bottom, in order, before you touch Lab 01.

## What you need before you start

- **An AWS account you control** — a new/personal sandbox account, never a shared or
  production account. No prior AWS experience is required; every command used later in the
  course is explained the first time it appears.
- **A card on file with AWS.** The free tier does **not** fully cover this course — see the
  cost breakdown below for exactly what to expect.
- **Basic command-line comfort** — running a command, reading its output, copy/paste. That's
  the whole bar.
- **AWS CLI v2** installed — check with:
  ```bash
  aws --version        # must show aws-cli/2.x
  ```
- **Terraform** installed (any recent 1.x) — check with:
  ```bash
  terraform version
  ```
- **`jq`** — recommended, not required. Scripts fall back to `--query` if it's missing.

## Step 1 — Set a budget alarm first

Your safety net if you forget to tear something down. Run the helper script (one command):

```bash
NB_BUDGET_EMAIL=you@example.com ./labs/00-prerequisites/set-budget.sh
# optional: NB_BUDGET_AMOUNT=15 NB_BUDGET_THRESHOLD=80
```

It creates a $10/month budget that emails you at 80%. Prefer the console? AWS Billing →
**Budgets** → create a budget for **$10–20/month** → alarm at 80%. (Lab 14 covers budgets in
depth — this is just the guardrail, done now, before you need it.)

## Step 2 — Deploy the sandbox environment

This is the one Terraform root every lab reads from — you apply it once, then each lab's
`break.sh` breaks part of it.

```bash
cd envs/sandbox
terraform init
terraform apply            # ~3-5 min: VPC, ALB, ASG, NAT Gateway
terraform output           # note app_url and asg_name
```

Open `app_url` in a browser. You should see the NorthBank digital-banking page. If it doesn't
load yet, wait ~60 seconds after `apply` finishes — the ASG needs to launch instances and the
load balancer needs a health-check cycle before it marks them healthy.

Full detail: [envs/sandbox/README.md](../../envs/sandbox/README.md).

## Step 3 — Know the cost before you start

Approximate US East on-demand pricing:

| Resource | While running |
|---|---|
| Application Load Balancer | ~$0.55/day |
| NAT Gateway | ~$1.10/day |
| 2× `t3.micro` (web tier) | ~$0.50/day |
| `db.t3.micro` RDS (labs 9, 11, 15 only) | ~$0.40/day extra |

**Full stack:** ~$2.15/day (~$2.55/day with the database on). Tear down after each session
(Step 4) and the realistic total for all 15 labs is **$5–15**. Leave it running by accident
and budget **$15–20/week** — bounded, but avoidable, which is what Step 1's alarm is for.

## Step 4 — Know how to tear down (you'll do this after every lab)

```bash
terraform -chdir=envs/sandbox destroy
```

Find anything left behind — everything is tagged `Project=NorthBank`:

```bash
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=NorthBank \
  --query 'ResourceTagMappingList[].ResourceARN' --output table
```

## Step 5 — Turn the database on only when a lab needs it

Off by default. Only labs 9, 11, and 15 need it:

```bash
terraform apply -var="create_database=true"     # before the lab
terraform apply -var="create_database=false"    # right after — this is the biggest cost risk
```

## You're ready when

- [ ] Budget alarm is set.
- [ ] `terraform apply` succeeded and `app_url` loads the NorthBank page in a browser.
- [ ] You know the `terraform destroy` command and you've located the leftover-finder command.
- [ ] You understand the database toggle and won't leave it on by accident.

---

*Next: [Lab 01 — The First 5 Minutes](../01-first-5-minutes/).*
