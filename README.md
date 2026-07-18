# AWS Day 2 Operations — Student Repo

Welcome! This is the hands-on companion repo for the **AWS Day 2 Operations** course. One
fictional company — **NorthBank**, a mid-sized retail bank — runs through every lab, so each
exercise feels like a real ticket landing on your board, not a disconnected demo.

## What's in this repo

```
docs/           Course theory & setup guides (read alongside the videos)
envs/sandbox/   The Terraform root you deploy — your lab environment
modules/        Terraform modules: base-network (VPC) + web-app (ALB/ASG/RDS)
labs/           The 15 troubleshooting labs (+ Lab 00 setup)
access/         Optional: scripts to set up IAM Identity Center (SSO) login
NORTHBANK-STORYLINE.md   The company backstory and cast of characters
```

Each lab folder has three files:

- **`incident.md`** — the ticket. Read this first; try to solve it on your own.
- **`break.sh`** — injects one realistic fault into your sandbox.
- **`GUIDE.md`** — the full walkthrough: diagnosis, fix, verify, plus a quick-reference
  reset at the end. Open it after you've tried cold — that's where the learning is.

## Getting started (in order)

1. **Read [docs/section-00-prerequisites.md](docs/section-00-prerequisites.md)** — tools,
   AWS account requirements, and cost expectations.
2. **Set a budget alarm** — `labs/00-prerequisites/set-budget.sh` (do this before anything else).
3. **Deploy the sandbox** — [docs/section-04-lab-setup.md](docs/section-04-lab-setup.md), or:
   ```bash
   cd envs/sandbox
   terraform init
   terraform apply
   ```
4. **Start with [Lab 01](labs/01-first-5-minutes/)** and work through in order —
   see [labs/README.md](labs/README.md) for the full lab list, cost controls, and the lab loop.

## ⚠️ Cost & safety

- **Sandbox account only.** The `break.sh` scripts deliberately break things — never point
  them at a real environment.
- Full stack costs **~$2.15/day** (~$2.55/day with the database on). Run
  `terraform destroy` after every session; realistic total for the whole course is **$5–15**.
- **RDS is off by default.** Only labs 9, 11, and 15 need it:
  `terraform apply -var="create_database=true"` — and turn it off right after.

## The docs folder

| Doc | What it covers |
|-----|----------------|
| [section-00-prerequisites.md](docs/section-00-prerequisites.md) | Tools, budget alarm, deploy, cost, DB toggle |
| [section-01-orientation.md](docs/section-01-orientation.md) | What the course is, meet NorthBank, how to use the repo |
| [section-02-access.md](docs/section-02-access.md) | How real companies log in: Identity Center, SSO, roles |
| [section-03-how-work-happens.md](docs/section-03-how-work-happens.md) | The operating rhythm: tickets, standup, the loops |
| [section-04-lab-setup.md](docs/section-04-lab-setup.md) | The Terraform modules and deploying the sandbox |
| [section-16-wrapup.md](docs/section-16-wrapup.md) | Cheat sheet, the maturity climb, your first 90 days |
| [terraform-explained.md](docs/terraform-explained.md) | Terraform from zero, for this repo |

Happy troubleshooting! 🚑
