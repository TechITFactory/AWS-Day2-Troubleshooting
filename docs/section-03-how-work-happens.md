# Section 3 — How the Job Actually Works  (~25m)  ← marketing clip

---

## Lesson 3.1 — Where you sit in the org  [🎬 · ~5m · 🎁]

You now know how to log in like the job does. But logging in isn't the job. So let me answer the question every fresher actually has and is slightly embarrassed to ask: what do you literally do all day?

Let's start with where you sit. A fresher pictures "an AWS person" — one hero in a hoodie. Reality is a team inside a structure. Here's the map at NorthBank.

### The teams around you

**Cloud Platform team** — this is where you are. You own the AWS environment that everyone else builds on. You manage the accounts, the networking, the security baseline, the monitoring and logging infrastructure. You respond to incidents. You keep the platform running.

**Application and Dev teams** — they build the banking applications that run on your platform. Marco leads one of these teams. They're your internal customers, and they file most of your tickets. "The app can't reach the database." "We need a new test environment by Friday." "Can you give me read access to the prod logs?"

**Security and GRC team** — Aisha works here. This team sends you security findings, audit requests, and compliance requirements. They'll ask for CloudTrail evidence, a report of who has production access, or remediation of a GuardDuty finding.

**Network Operations** — they own the hybrid connectivity. Direct Connect links back to NorthBank's on-premises core banking system. VPN tunnels. The network backbone.

**Managers, Product Owner, Scrum Master** — Dana runs the standup. These people set priorities, run the ceremonies, and make sure work is flowing.

**On-call rotation** — every few weeks, you're the first responder for a week. When something breaks at 2am, you're the one who gets paged.

### Fresher vs 10-year — same board, different altitude

Here's the part that matters. A fresher and a senior sit in the same standups, pull from the same board. The difference isn't the ceremony — it's the altitude.

A **fresher** picks up scoped tickets, shadows on-call, runs documented runbook tasks. "Restore this RDS snapshot." "Add this user to the PowerUser group." "Check why this alarm fired." That's not a lesser job — that's exactly the right job for month one. You're learning the environment, building confidence, getting familiar with the tools and the rhythm.

A **senior** owns the architecture decisions, unblocks everyone else, takes the ambiguous 3am incident that has no runbook, mentors the team, and represents the platform team in design reviews.

Same board, different altitude. If you're new, you're supposed to be at the low altitude — that's the design, not a demotion. And if you're senior watching this: yes, this is the model you already run. Now you have language to explain it to your own juniors.

---

## Lesson 3.2 — A day in the life  [🎬 · ~5m]

Let me walk you through an actual day, in order. This is the shape nobody shows you.

**Step 1: Log in** — the real way, from Section 2. SSO portal, assume your role, `aws sso login` for the CLI, then `aws sts get-caller-identity` to confirm who you are and which account you're in.

**Step 2: Check the overnight** — before anything else, you check what happened while you were asleep. Alarms that fired. Failed backups. On-call handover notes. Pipeline failures. Cost-anomaly emails. New security findings in GuardDuty or Security Hub. You scan the notifications, triage anything urgent, and get a sense of the environment's health.

**Step 3: Standup** — 15 minutes, standing or on Zoom. What you did yesterday, what you'll do today, blockers. That's it. You're not presenting a detailed status report. You're synchronizing with the team.

**Step 4: Work your sprint tickets** — the planned work you pulled from the board. "Set up automated patching for the web tier." "Investigate the cost spike in the nonprod account." "Write a runbook for RDS failover."

**Step 5: Handle interrupts** — ops is planned work plus interrupts. An access request comes in. Someone pings you: "the app can't reach the DB." An alarm fires. A developer needs help debugging an IAM permission issue. The interrupts don't respect your plan. You context-switch, triage, fix or escalate, document, and get back to your sprint work.

**Step 6: Update tickets and document** — you move cards on the board, write notes in the ticket, update a runbook, post a summary in Slack. If it isn't written down, it didn't happen. Documentation is part of the job, not a bonus task you do if you have time.

**Step 7: End of day / on-call handover** — you leave the environment and the board in a known state so the next person — or tomorrow-you — isn't guessing. If you're handing off to the next on-call shift, you write a short summary: what's in progress, what's unstable, what to watch.

### The honest truth

Here's the thing I wish someone had told me: it is not eight hours of terminal. It's tickets, standups, a couple of Slack threads, a code or change review, and then bursts of real troubleshooting.

If you came in expecting to hack in a dark room all day, the reality feels weird — like you're not doing "real" work. You are. The tickets, the documentation, the standup — that is the job. The terminal bursts are the exciting 20 percent.

---

## Lesson 3.3 — The agile slice ops actually touches  [🎬 · ~5m]

You're going to hear a lot of agile vocabulary. I'm going to save you time and teach you only the slice that actually touches an ops person. The rest is mostly the dev teams' world.

### The slice that touches you

**There's a board, and you pull work from it.** Columns typically look like: To Do → In Progress → Review → Done. There's also an Expedite or Incident lane for things that jump the queue. That SEV-1 incident at 10am doesn't wait for the next sprint.

**Daily standup** — this is the one ceremony you're really in. Did, will do, blockers. It's short. It's daily. That's the synchronization point.

**Planned work plus interrupts** — your sprint tickets plus incidents and requests that ignore sprint boundaries. This is why ops teams often lean toward Kanban over strict Scrum. Scrum wants you to commit to a fixed set of work for a two-week sprint. Ops reality is one continuous line of work with interrupts that can't wait.

**Ticket types you'll actually get:**
- Access request — "give me PowerUser in nonprod"
- Alarm or incident — "the site is down," "RDS CPU is at 90%"
- Patching task — "patch the web tier this maintenance window"
- Cost optimization task — "the bill jumped 40%, investigate"
- Change request — "resize the RDS instance"
- Audit evidence request — "pull the CloudTrail logs for last quarter"
- Provisioning request — "build a new test environment"
- Security finding remediation — "GuardDuty found exposed credentials"

Every lab in this course is one of these ticket types.

**Change management** — planned production changes go through an approval process and a maintenance window. You do not just click around in production. You write a change ticket. You get approval. You schedule a window. You execute the change. You verify. You document. This is the reflex that separates a pro from a cowboy.

### What you can ignore

You'll hear *sprint, story points, velocity* — that's mostly the dev teams' world. As ops, your reality is the board, the standup, and the change process. That's the part that affects you. Learn that, nod along to the rest.

---

## Lesson 3.4 — The cadence: nested loops  [🎬 · ~7m]  ← the centerpiece

Day 2 operations is not a to-do list you finish. It's a set of loops running at different speeds — a daily loop inside a weekly loop inside a monthly loop inside a quarterly loop — with one long project threaded through all of them. Let me build that up.

### Today — the daily loop

Every day:
- Log in and check the overnight. What alarms fired? Did backups succeed? What did the on-call person hand off?
- Standup. Synchronize with the team.
- Work your sprint tickets. Handle access requests and interrupts.
- Respond to any alarm or incident. Update and close tickets.

The daily loop runs every workday. It's the heartbeat.

### This week — the weekly loop

Every week, in addition to the daily loop:
- Sprint work progresses. Mid-sprint check-ins if you're running sprints.
- **Weekly patch review or scheduled patch window.** You review available patches, test in nonprod, schedule the prod window, apply patches, verify.
- **Review the security findings backlog.** GuardDuty, Security Hub, Config. Pick a few, triage them, remediate, close. Burn down the backlog a little each week.
- **On-call handover at the week boundary.** The outgoing on-call writes a short summary for the next person.
- **Cost check.** Anything trending up? Any anomalies?

The weekly loop turns about 50 times a year.

### This month — the monthly loop

Every month, in addition to daily and weekly:
- **Sprint review and retrospective.** Demo what shipped. What went well? What didn't? What will we change next sprint?
- **Monthly cost review with the team or manager.** Dive into the bill. Rightsizing actions. Turn off idle resources.
- **Access review.** Who has what? Remove stale access. Someone left the company three months ago — do they still have a user? Someone changed roles — do they still need prod access? Auditors ask for this. Compliance requires it.
- **Backup restore test.** Don't just assume backups work. Actually restore something to prove it. Pick a snapshot, restore it, verify the data is there.
- **Patch compliance report.** Are we up to date? Close the gaps.
- Small improvements. Automate something that was manual. Add an alarm that was missing. Update a runbook.

The monthly loop turns 12 times a year.

### This quarter — the quarterly loop

Every quarter, in addition to daily, weekly, and monthly:
- **Disaster recovery drill.** Failover test. Can we actually fail over to the DR region? How long does it take? Measure RTO (Recovery Time Objective) and RPO (Recovery Point Objective). Document the results. Fix what broke.
- **Audit evidence cycle.** PCI, SOX, central bank regulators. Pull CloudTrail logs, Config snapshots, access reports. Package them for the auditors.
- **Well-Architected or architecture review.** Step back and look at the big picture. What tech debt needs tackling? What's brittle? What should we redesign?
- **Capacity and budget planning for next quarter.** Forecast growth, plan spend, request budget.

The quarterly loop turns 4 times a year.

### Six months / ongoing — the project arc

Over six months or a year, a big migration or platform initiative progresses in sprint-sized slices.

For NorthBank, that's the cloud migration. Move the digital banking platform to AWS, service by service, without a customer-facing outage. Each sprint might migrate one service, or add one piece of the landing zone, or roll out Infrastructure as Code to one more account.

**Every loop above keeps running underneath the initiative.** The migration doesn't pause the daily standup or the monthly access review. The daily, weekly, monthly, and quarterly loops keep turning while the long project moves forward in the background.

And over those six months, the environment gets steadily more automated, more monitored, more compliant. That **maturity climb** is the six-month story:

**Month 1:** Manual and reactive. Alarms are missing. Nobody's tested a restore. Access is sprawling. Prod changes are ad hoc.

**Month 6:** Automated and proactive. Alarms and dashboards exist. Backups are restore-tested monthly. Access is reviewed and scoped. Patching is on a schedule. Prod changes go through change control. Security findings are triaged weekly.

Many of the labs in this course are literally a step on that maturity climb: adding the missing alarm (Lab 2), proving backups work (Lab 11), putting patching on rails (Lab 12), burning down security findings (Lab 13).

### The mental model

Picture it: a **daily loop** inside a **weekly loop** inside a **monthly loop** inside a **quarterly loop**, and a **six-month project** running like a thread through all of them.

That's Day 2. Not a checklist you complete — loops you keep turning, getting a little more mature each turn. That single picture is the thing a fresher is missing, and I promise the veterans watching are nodding right now.

---

## Lesson 3.5 — The NorthBank storyline one-pager  [📄 · ~2m]

Everything from here runs through **NorthBank** — our bank migrating its platform to AWS.

Every lab is a NorthBank ticket. Every loop we just talked about is a NorthBank event: the monthly access review, the quarterly DR drill, the "app can't reach the DB" incident.

That's on purpose — because why you do this work only makes sense when there are real customers, real auditors, and a real bill on the line. A bank makes uptime, compliance, cost, and change control all concrete and non-negotiable.

The full NorthBank storyline is in [NORTHBANK-STORYLINE.md](../NORTHBANK-STORYLINE.md). It covers:
- The company — 4 million customers, retail bank, cloud migration approved 18 months ago
- The five-account structure — management, security, logging, prod, nonprod
- The people — Priya (your team lead), Marco (app team), Aisha (security), Tom (Finance), Dana (Scrum Master)
- The six-month arc — manual and reactive to automated and proactive

Every time a lab feels abstract, tie it back to NorthBank. That's why the context matters.

---

## Lesson 3.6 — Quiz: The operating model  [❓ · ~1m]

Quick check to lock in the concepts:

- What's the difference between a fresher and a senior on the same team? (Same board, different altitude — juniors take scoped tickets, seniors own architecture and ambiguous incidents)
- What are the two types of work that fill an ops day? (Planned work plus interrupts)
- Name the four loop frequencies. (Daily, weekly, monthly, quarterly)
- Why don't you just click around in production? (Change management — prod changes go through approval and a maintenance window)

---

Next up: Part C — fifteen tickets land on your board, and we diagnose and fix every one. Let's get to work.
