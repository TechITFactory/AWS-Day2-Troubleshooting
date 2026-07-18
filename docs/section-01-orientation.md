# Section 1 — Welcome & Orientation  (~6m)

---

## Lesson 1.1 — What this course is (and who it's for)  [🎬 video · ~2m · 🎁 preview]

Welcome to AWS Day 2 Operations and Troubleshooting.

The term "Day 2" refers to everything that happens *after* you build something. Day 1 is about setup and getting things running for the first time. Day 2 is the real job — keeping things running, fixing issues when they break, and responding to the problems that show up in production.

This course teaches two things together. First, the human side — how the job actually works in a real company. What your day looks like, who you work with, how tickets move through a board, and what happens daily versus monthly versus quarterly. Second, the technical side — 15 hands-on troubleshooting labs where you diagnose and fix real incidents.

This course is built for two audiences at the same time. If you're starting fresh, you'll learn what day one on a cloud operations team feels like. If you've been doing this work for years, you'll finally see the operating model written down clearly — something you can use to train others or standardize your runbooks.

By the end of this course, you'll be able to log in the way real companies do, read the work board, and fix the incidents that actually show up in the queue.

---

## Lesson 1.2 — Meet NorthBank (our story)  [🎬 video · ~2m · 🎁 preview]

Everything in this course runs through one fictional company: **NorthBank**.

NorthBank is a mid-sized retail bank with 4 million customers. They have a mobile app, an internet banking portal, an ATM network, and a core banking system that still runs partly on-premises. Eighteen months ago, the board approved a cloud migration — move the digital banking platform to AWS, service by service, without a single customer-facing outage.

You're joining the **Cloud Platform team** — the team that owns the AWS environment everyone else builds on.

The reason this course uses a bank is that uptime, compliance, cost, and change control are all very real in banking. An outage means customers can't reach their money. PCI-DSS, SOX, and central bank regulators all audit the company. Finance watches the cloud bill closely. You don't just click around in production — changes go through approvals and maintenance windows. A bank makes all of these Day 2 concerns concrete and non-negotiable.

Every lab is framed as a NorthBank ticket. Every compliance check, every alarm, every cost spike — it all has a real reason behind it.

NorthBank runs a **multi-account AWS Organization**:

- `northbank-management` — the organization root, billing, and IAM Identity Center
- `northbank-security` — GuardDuty and Security Hub aggregation, log archive
- `northbank-logging` — centralized CloudTrail and Config logs
- `northbank-prod` — the customer-facing banking platform
- `northbank-nonprod` — dev, test, and staging environments

You log in through **IAM Identity Center** (the SSO portal), get assigned a role per account, and your access is deliberately less than a senior's — that's how least privilege works in a real company.

Inside the nonprod and prod accounts, the digital banking web tier follows a standard shape: a VPC with an Application Load Balancer, an Auto Scaling group of web servers, and an RDS database. This is the system the labs will break — and you'll fix.

---

## Lesson 1.3 — How to use this course + repo  [📄 article · ~2m]

Everything you need lives in this repository: lecture scripts, login automation scripts, Terraform code to build the lab environments, and the 15 troubleshooting labs themselves.

### Repo structure

```
.
├── README.md                     # overview and repo guide
├── NORTHBANK-STORYLINE.md        # the full NorthBank backstory
├── course/                       # lecture scripts for Part A and Part B
├── access/                       # SSO setup automation (Part B demo)
├── modules/                      # Terraform modules (base-network + web-app)
├── labs/                         # 15 troubleshooting labs
│   ├── README.md                 # cost controls and conventions
│   └── NN-<slug>/                # each lab has README, break script, solution, and script
└── delivery/                     # Udemy section/lesson delivery notes
```

### One critical rule

**Use a throwaway sandbox account.** Every lab in this course deliberately breaks things. Never point these scripts at a real AWS account with production workloads or customer data.

### Recommended order

1. **Section 2: Real-World AWS Access** — learn how companies actually log in (IAM Identity Center, multiple accounts, SSO roles). This section is free preview content.
2. **Section 3: How Work Happens** — understand the operating rhythm, the board, standup, and the daily/weekly/monthly/quarterly loops that structure the job.
3. **Sections 5–15: The Labs** — 15 troubleshooting scenarios, each framed as a NorthBank ticket. You'll deploy the infrastructure with Terraform, run the break script, diagnose the issue, fix it, and verify the fix.

One key file guides the course:

- [NORTHBANK-STORYLINE.md](../NORTHBANK-STORYLINE.md) — the company backstory, the cast of characters, and the six-month maturity climb

Each lab follows the same pattern: **symptom → diagnose → fix → verify**. The incident.md gives you the ticket and the symptoms. The GUIDE.md walks through the full diagnosis and fix.

You'll use Terraform to build the lab environments. The two core modules are:

- **base-network** — the VPC foundation (subnets, routing, security groups)
- **web-app** — the application tier (ALB, Auto Scaling group, optional RDS)

Most labs break something in the web-app module. You'll apply the infrastructure, break it, fix it, then destroy it to keep costs low.

### Cost and safety

All labs use the smallest instance sizes. RDS is off by default unless a lab needs it. Budget alarms are included in the Terraform. Always run `terraform destroy` after each lab session. See [labs/README.md](../labs/README.md) for full cost controls and teardown instructions.

### What you'll walk away with

By the end of this course:

- You'll know how to log in the way real companies do — through IAM Identity Center, with scoped roles and multiple accounts
- You'll understand what a normal day, week, month, and half-year looks like on a cloud operations team
- You'll be able to diagnose and fix the 15 most common incidents that land in the queue — from "the site is down" to "the bill jumped 40%" to "the app can't reach the database"
- You'll have a one-page troubleshooting cheat sheet and a working mental model of the triage spine: who am I → what changed → read front-door-in → hypothesis → test → fix → verify

If you're a fresher, day one won't be a shock. If you're a 10-year veteran, you'll have a clean, teachable articulation of the operating model you already live.

Let's get started.
