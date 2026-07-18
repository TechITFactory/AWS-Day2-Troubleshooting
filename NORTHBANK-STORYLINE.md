# NorthBank — The Storyline That Carries the Course

> One fictional company runs through every section. These facts stay consistent throughout the course so it feels like one continuous world, not a pile of disconnected labs.

## The company

**NorthBank** is a mid-sized retail bank. It has 4 million customers, a mobile app, an
internet-banking web portal, an ATM network, and a core banking system that still runs partly
on-prem. Eighteen months ago the board approved a **cloud migration**: move the digital
banking platform to AWS, service by service, without a single customer-facing outage.

You are a new joiner on the **Cloud Platform team** — the team that owns the AWS environment
everyone else builds on.

## Why a bank (and why it matters for every lab)

A bank makes the *why* behind Day 2 work concrete and non-negotiable:

- **Uptime** — an outage means customers can't reach their money. Incidents are real.
- **Compliance** — PCI-DSS, SOX, and the central-bank regulator all audit NorthBank. This is
  why access reviews, CloudTrail, Config, backups, and DR drills aren't optional busywork.
- **Cost** — Finance watches the cloud bill; runaway spend becomes *your* ticket.
- **Change control** — you do not click in production. Prod changes go through an approval and
  a maintenance window. A bank teaches this reflex better than any other example.

Every time a lab feels abstract, tie it back: *"NorthBank is a bank — here's why this bites."*

## The environment (the shape students should picture)

NorthBank runs a **multi-account AWS Organization**:

| Account | Purpose |
|---------|---------|
| `northbank-management` | Org root, billing, IAM Identity Center |
| `northbank-security` | GuardDuty/Security Hub aggregation, log archive |
| `northbank-logging` | Centralized CloudTrail + config logs |
| `northbank-prod` | Customer-facing banking platform |
| `northbank-nonprod` | Dev / test / staging |

You log in through **IAM Identity Center (SSO)**, get assigned a **role** (permission set) per
account, and your access is deliberately *less* than a senior's. That's Part B.

Inside `nonprod` and `prod`, the digital-banking web tier is a standard shape: a **VPC**
(`base-network`) with an **ALB → Auto Scaling group of web servers → RDS** app
(`web-app`). This is the thing the labs break. It maps to the two Terraform modules in
[`modules/`](modules/).

## The people (recurring cast for tickets)

- **You** — new joiner, Cloud Platform team. Pick up scoped tickets, shadow on-call.
- **Priya** — your team lead / senior SRE. Owns architecture, unblocks you, runs change reviews.
- **The App team (led by Marco)** — build the banking app; file most of your tickets
  ("the app can't reach the DB").
- **Security/GRC (Aisha)** — sends findings, audit-evidence requests, access-review nudges.
- **Finance (Tom)** — monthly cost review; the source of cost-optimization tickets.
- **Scrum Master / PO (Dana)** — runs standup, sets sprint priorities.

## The arc (the six-month story, shown as a maturity climb)

The migration progresses in sprint-sized slices while the daily/weekly/monthly/quarterly loops
run underneath it (see Part A4). The through-line:

- **Month 1** — manual and reactive. Alarms are missing, nobody's tested a restore, access is
  sprawling, prod changes are ad hoc.
- **Month 6** — automated and proactive. Alarms and dashboards exist, backups are restore-tested,
  access is reviewed, patching is on a schedule, and prod changes go through change control.

That climb *is* the six-month story. Many labs are literally a step on it: adding the missing
alarm (lab 2), proving backups work (lab 11), putting patching on rails (lab 12), burning down
security findings (lab 13).

## Ticket convention (used across all labs)

Every lab opens as a NorthBank ticket so the framing is uniform:

```
Ticket:   NB-<lab#><seq>       e.g. NB-1401
Reporter: <cast member>        e.g. Marco (App team)
Severity: SEV-1 | SEV-2 | SEV-3 | Request
Title:    <one-line symptom the reporter sees>
```

SEV-1/2 are incidents (they can jump the sprint via the Expedite/Incident lane). Requests and
SEV-3s are planned work you pull from the board. That distinction — **planned work +
interrupts** — is the core ops reality Part A teaches, and the labs make it tangible.
