# The 15 Troubleshooting Labs

Each lab is a **NorthBank ticket**: a symptom lands on your board, you **diagnose**, you **fix**,
and you take away one Day-2 lesson. Every lab follows the same three-file shape so the rhythm is
predictable.

## The three files in every lab

| File | What it is |
|------|------------|
| `incident.md` | The ticket: symptom, what's expected of you, time & cost. **Start here.** |
| `break.sh` | Injects **one** realistic fault into your deployed sandbox. Run it, then diagnose. |
| `GUIDE.md` | The full walkthrough: story, diagnosis commands, fix, verify, and a quick-reference reset. **Open it after you've tried on your own.** |

The diagnosis flow is always the same spine — the **First 5 Minutes** triage from Lab 01:
*who/where am I → what changed → read the symptom at the right layer → form one hypothesis →
test it → fix → verify.*

## The 15 labs (+ Lab 00 setup)

| # | Lab | Module(s) needed | Ticket type | ⭐ |
|---|-----|------------------|-------------|----|
| 00 | [Prerequisites & environment setup](00-prerequisites/) | — | Setup (do once) | |
| 01 | [The First 5 Minutes (triage flow)](01-first-5-minutes/) | web-app | Incident | |
| 02 | [CloudWatch monitoring & alarms](02-cloudwatch-monitoring/) | base-network + web-app | Alarm/incident | |
| 03 | [Log troubleshooting (Logs Insights)](03-logs-insights/) | web-app | Incident | |
| 04 | [EC2 troubleshooting](04-ec2-troubleshooting/) | base-network + web-app | Incident | |
| 05 | [IAM & permissions ("Access Denied")](05-iam-access-denied/) | web-app | Request/incident | ⭐ |
| 06 | [Networking (SG / NACL / routes)](06-networking/) | base-network + web-app | Incident | ⭐ |
| 07 | [Load balancer & target health](07-load-balancer/) | base-network + web-app | Incident | |
| 08 | [Auto Scaling issues](08-auto-scaling/) | base-network + web-app | Incident | |
| 09 | [RDS troubleshooting](09-rds/) | web-app (`create_database=true`) | Incident | ⭐ |
| 10 | [S3 troubleshooting](10-s3/) | (standalone) | Incident/request | |
| 11 | [Backups & restore (actually restore!)](11-backups-restore/) | web-app (`create_database=true`) | Monthly task | |
| 12 | [Patching with Systems Manager](12-patching-ssm/) | web-app | Patching task | |
| 13 | [Security findings triage (GuardDuty/Hub/Config)](13-security-findings/) | web-app | Security finding | |
| 14 | [Cost troubleshooting](14-cost/) | (account-wide) | Cost task | |
| 15 | [Incident simulation (capstone)](15-incident-sim/) | base-network + web-app (`create_database=true`) | SEV-1 capstone | |

> ⭐ = the highest-leverage labs — the skills you'll use most on the job.

See the [one-page cheat sheet](CHEATSHEET.md) for the whole course at a glance.

---

## Prerequisites & cost

**Do [Lab 00 — Prerequisites & environment setup](00-prerequisites/) first.** It covers the
tools you need, deploying the sandbox, the full per-resource cost breakdown, and setting a
budget alarm — before you touch Lab 01. Quick summary: full stack ~$2.15/day
(~$2.55/day with the database on), realistic total for all 15 labs **$5–15** if you tear down
after each session.

## Cost & safety controls — read before running any `break.sh`

> **Sandbox account only.** Never point a `break.sh` at anything real. These scripts
> deliberately break things.

- **Smallest sizes:** `t3.micro` / `db.t3.micro`, single-AZ, one NAT Gateway. Defaults are set
  low in the modules — don't scale them up for a lab.
- **RDS is off by default** (`create_database = false`). Only enable it for labs 9, 11 & 15,
  and turn it off immediately after — a running RDS is the biggest lab-bill surprise.
- **Tear down every lab:** `terraform destroy` when you're done. The modules tag everything with
  `Project=NorthBank` so you can audit leftovers:
  ```bash
  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=NorthBank \
    --query 'ResourceTagMappingList[].ResourceARN' --output table
  ```
- **Budget alarm:** set a small AWS Budgets alert (e.g. $20) on the sandbox account before you
  start — Lab 00 includes `set-budget.sh` for this. Do it first so a mistake pages *you*, not
  your credit card statement.
- **Every `break.sh` is reversible.** The fix is in the matching `GUIDE.md`; where a break
  isn't auto-reversible, the guide's Quick reference documents the exact reset step.

## Conventions used by every `break.sh`

- `set -euo pipefail`, reads `AWS_REGION` (default `us-east-1`) and standard resource IDs from
  env or `terraform output`.
- Prints the **symptom you should see**, and writes what it actually broke to
  `.break-state.json` in the lab dir — don't peek until you've diagnosed; some fix commands
  read IDs from it.
- Injects **exactly one** fault. Labs stay single-root-cause except the capstone (Lab 15), which
  intentionally chains several.

## The lab loop

```bash
terraform -chdir=envs/sandbox apply         # build the environment once (see envs/sandbox/README.md)
cd labs/NN-<slug>
cat incident.md                             # read the ticket
./break.sh                                  # inject the fault (reads terraform outputs)
# ...diagnose on your own first, then follow GUIDE.md to check your work...
terraform -chdir=envs/sandbox destroy       # tear down when done for the day
```

> The [`envs/sandbox`](../envs/sandbox/) root wires `base-network` + `web-app` together and exposes
> the outputs (`asg_name`, `alb_arn`, `target_group_arn`, …) that each lab's `break.sh` reads.
> Labs 9, 11, and 15 need the database — apply with `-var="create_database=true"`.
