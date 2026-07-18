# NorthBank Day-2 Troubleshooting Cheat Sheet

> One page. Print it. This is the whole course compressed into what you'd actually reach for at
> 3 a.m.

## The triage spine (works for ANY incident)

1. **Who / where am I?** → `aws sts get-caller-identity`
2. **What changed?** → CloudTrail `lookup-events` (most incidents are a recent change)
3. **Read the symptom front-door-in** (ALB → target → instance → app → DB)
4. **One hypothesis, out loud**
5. **Test it** (cheaply)
6. **Smallest fix**
7. **Verify + communicate** (and re-check — there may be a second fault)

## First commands by symptom

| Symptom | Start here |
|---------|-----------|
| 503 at the ALB | `elbv2 describe-target-health` → no/unhealthy targets? |
| Targets unhealthy | read the **reason code** (below) |
| "Access Denied" | read who/what/resource → `iam simulate-principal-policy` |
| App can't reach DB | **reach vs refuse**: timeout = network, refused = capacity/auth |
| Instance up, app dead | `ec2 describe-instance-status` (running ≠ healthy) → SSM in |
| Intermittent errors | CloudWatch **Logs Insights**: count by status → filter → group |
| ASG not scaling/healing | `describe-auto-scaling-groups` → `SuspendedProcesses`; activity history |
| Bill jumped | hunt unattached EIPs / `available` volumes / idle NAT & RDS |

## Target health reason codes (Labs 06/07)

- `Target.Timeout` → **can't connect** → network (SG / NACL / route) — **Lab 06**
- `Target.ResponseCodeMismatch` → connected, wrong HTTP code → **health-check config** — **Lab 07**
- `Target.FailedHealthChecks` → generic → check the app + path/matcher

## The rules that save you

- **Explicit `Deny` always wins** (IAM + bucket policies). Simulator says `explicitDeny` → hunt a Deny.
- **`running` ≠ `healthy`.** EC2 state ≠ your app working.
- **"Available" ≠ reachable** (RDS is up ≠ app can connect); **"available" volume = attached to nothing.**
- **SG = stateful** (reply auto). **NACL = stateless** (allow both directions).
- **`bucket` vs `bucket/*`** = the container vs the objects inside it.
- **Reach vs refuse** is the first question for any datastore.
- **A backup you've never restored is a hope, not a backup.**
- **You can't patch what you can't manage** (SSM = agent + role + network).
- **Every security finding gets a disposition** (fixed / suppressed+reason / accepted+owner).
- **Fix with least privilege** — a wide-open shortcut today is a finding next quarter.
- **Real incidents have layered causes** — verify after every fix; re-read the symptom.

## The network path walk (Lab 06)

`Security Group` → `NACL` → `Route table` → `is it listening` — in that order, every time.
Prove it with **VPC Reachability Analyzer**.

## Get onto a box (no SSH)

`aws ssm start-session --target <instance-id>` — no keys, no port 22, fully logged.

## Cost & safety

- Sandbox account only. `terraform destroy` after each lab.
- RDS off unless the lab needs it (`create_database=true`), then off again.
- Set an AWS Budget so a spike pages **you**, not Finance.
- Find leftovers: `resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=NorthBank`

## The mental model (Part A)

Day 2 = **nested loops**: daily inside weekly inside monthly inside quarterly, with a 6-month
project threaded through. Maturity climb: **month 1 manual + reactive → month 6 automated +
proactive.** Every incident you close should leave behind an alarm, a runbook, or a guardrail.
