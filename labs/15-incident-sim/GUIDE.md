# Lab 15 — Capstone: SEV-1, everything's on fire (chained faults) 🎓

The finale. Unlike Labs 1-14, this incident has more than one root cause — no single check explains everything. You'll use the triage spine, target health reason codes, the network walk, and reach-versus-refuse, all in one incident.

⚠️ **Important:** This lab needs the full stack including the database. Turn it on before the lab, turn it off immediately after.

---

## Lab 15: SEV-1 — everything's on fire (chained faults)

### What we'll do in this lab

- Orient: identity, then read the front door
- Fix the network fault, then verify — don't assume you're done
- Fix the health-check fault and confirm the site returns 200
- Find and fix the hidden third fault blocking the database
- Turn the paused auto-scaling automation back on
- Write the post-incident timeline, root causes, and follow-ups

### The ticket

```
Ticket:   NB-1501
Reporter: PagerDuty (automated) → you are on-call
Severity: SEV-1
Title:    "Internet banking is DOWN. Customers can't log in or move money.
           The clock is running."
```

Every previous lab had exactly one root cause: fix the security group, done; fix the health check, done. This lab has more than one thing broken at once — internet banking is down, and there's more than one cause.

You'll use everything so far: the triage spine (Lab 01), target health reason codes (Labs 06/07), the network walk (Lab 06), reach-versus-refuse (Lab 09).

The habit that matters most: **fix one thing, verify, then re-read the symptom before touching the next thing.** Don't declare victory until the customer journey works end to end.

### Turn the full stack on, then trigger the incident

```bash
terraform -chdir=../../envs/sandbox apply -var="create_database=true"
```

Wait for it to become available. Then break everything:

```bash
cd labs/15-incident-sim
export AWS_REGION=us-east-1
export APP_SG=$(terraform -chdir=../../envs/sandbox output -raw app_security_group_id)
export ALB_SG=$(terraform -chdir=../../envs/sandbox output -raw alb_security_group_id)
export DB_SG=$(terraform -chdir=../../envs/sandbox output -raw db_security_group_id)
export TG_ARN=$(terraform -chdir=../../envs/sandbox output -raw target_group_arn)
export ALB_DNS=$(terraform -chdir=../../envs/sandbox output -raw alb_dns_name)
export ASG_NAME=$(terraform -chdir=../../envs/sandbox output -raw asg_name)
./break.sh
```

Three faults injected:
1. Security group rule removed: load balancer can't reach the app tier
2. Health check path changed to `/healthz` (doesn't exist)
3. Security group rule removed: app tier can't reach the database

`break.sh` also pauses the app tier's auto-scaling self-healing (`ReplaceUnhealthy`/`AZRebalance`)
before injecting anything. Without that, the ASG would keep terminating and relaunching
"unhealthy" instances into the same broken state while you're mid-diagnosis — fighting your own
automation during a SEV-1 is how you turn one incident into three. You'll turn it back on once
the incident is verified resolved.

### Phase 0: Orient

Start with the spine. Who and where am I:

```bash
aws sts get-caller-identity
```

Right account. Read the front door:

```bash
curl -i "http://$ALB_DNS/"
```

```
HTTP/1.1 503 Service Temporarily Unavailable
```

503, no healthy targets — same starting point as Lab 01. Don't start flipping switches. Work the spine: orient, read the symptom, one hypothesis, test, fix, verify, repeat.

### Phase 1: Front door in — read target health

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
```

All targets unhealthy. You may see `Target.Timeout` on some, `Target.ResponseCodeMismatch` on others, or both — seeing more than one reason code is a hint that more than one thing is broken.

First hypothesis: the network is blocking the load balancer from reaching the app tier (Lab 06). Test it.

### Phase 2: Fix the network fault — then don't assume you're done

```bash
aws ec2 describe-security-groups --group-ids "$APP_SG" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]' \
  --output json
```

The rule allowing port 80 from the ALB's security group is missing. Fix it:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$APP_SG" \
  --protocol tcp --port 80 \
  --source-group "$ALB_SG"
```

Rule restored. Now the trap: don't declare victory. Wait 30 seconds, re-check target health:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' \
  --output text
```

Still unhealthy. Re-read the reason code:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.Reason' \
  --output text
```

```
Target.ResponseCodeMismatch
```

It was `Target.Timeout` before — couldn't connect. Now it's `Target.ResponseCodeMismatch` — connected fine, wrong HTTP response. A second, independent fault, hidden behind the same symptom. This is why you verify after every change.

### Phase 3: Fix the health-check fault

`Target.ResponseCodeMismatch` means a misconfigured health check (Lab 07). Check it:

```bash
aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" \
  --query 'TargetGroups[0].HealthCheckPath' \
  --output text
```

```
/healthz
```

The app serves `/health`, not `/healthz`. Fix it:

```bash
aws elbv2 modify-target-group \
  --target-group-arn "$TG_ARN" \
  --health-check-path /health
```

Wait 30 seconds, verify:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' \
  --output text
```

```
healthy healthy
```

Test the front door:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB_DNS/"
```

```
200
```

The homepage loads. Not resolved yet — an incident means "customers can bank," not "the homepage loads." Test the actual customer journey.

### Phase 4: The hidden third fault

```bash
curl -s "http://$ALB_DNS/balance"
```

Works, returns account balance.

```bash
curl -s "http://$ALB_DNS/transfer"
```

Hangs, times out after 30 seconds. Customers can see their balance but can't move money — still an outage for a bank.

Apply Lab 09's fork: reach or refuse? It times out — that's reach, a network problem to the database.

```bash
aws ec2 describe-security-groups --group-ids "$DB_SG" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`3306`]' \
  --output json
```

The rule allowing port 3306 from the app tier is missing. Fix it:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$DB_SG" \
  --protocol tcp --port 3306 \
  --source-group "$APP_SG"
```

Verify:

```bash
curl -s "http://$ALB_DNS/transfer" -d "amount=100"
```

Transfer succeeds. Three faults fixed, incident resolved — verified end to end, not just "the site loads."

### Phase 5: Turn the automation back on

One thing was running quietly in the background this whole time: `break.sh` paused the
auto-scaling group's self-healing before touching anything, so it wouldn't cycle instances
underneath you mid-diagnosis. Now that the incident is verified resolved, turn it back on:

```bash
aws autoscaling resume-processes --auto-scaling-group-name "$ASG_NAME" \
  --scaling-processes ReplaceUnhealthy AZRebalance
```

Leaving automation suspended is its own footgun for the next person — don't skip this step.

### Phase 6: The post-incident write-up

**Incident timeline:**

```
10:37 - Paged by PagerDuty: internet banking down, 503 at front door
10:38 - Verified identity and account, confirmed 503
10:39 - Read target health: all unhealthy, reason Target.Timeout
10:40 - Diagnosed network fault: app SG missing rule from ALB
10:41 - Fixed: restored ALB→app:80 security group rule
10:42 - Verified: targets STILL unhealthy, reason now ResponseCodeMismatch
10:43 - Diagnosed health check fault: TG health check pointed at /healthz
10:44 - Fixed: changed health check path to /health
10:45 - Verified: targets healthy, site returns 200
10:46 - Tested customer journey: balance works, transfers fail (timeout)
10:47 - Diagnosed third fault: DB SG missing rule from app tier
10:48 - Fixed: restored app→DB:3306 security group rule
10:49 - Verified: transfers work end-to-end
10:50 - Incident resolved
10:51 - Resumed ASG auto-healing (ReplaceUnhealthy/AZRebalance), paused since the start
```

Total: 13 minutes from page to resolution.

**Root causes (blameless):** three security group rules were removed from production, likely during separate troubleshooting sessions, and stacked into a complete outage:
1. Load balancer couldn't reach the app tier (network)
2. Health check misconfigured (load balancer)
3. App tier couldn't reach the database (network)

No single person caused this — multiple changes accumulated, which is why change control matters.

**Follow-ups:**
1. **Unhealthy-hosts alarm from Lab 02** — should have paged the moment targets went unhealthy, not when a customer reported 503.
2. **App-5xx alarm from Lab 03** — catches database connectivity failures immediately.
3. **Change control on production security groups** — changes should go through a change ticket and maintenance window (Lab 12); consider Config Rules to detect ad hoc modifications.
4. **Least-privilege review** — why did this role have permission to modify production security groups directly? Review IAM roles and permission sets (Labs 5, 8, 13).
5. **Runbook update** — document this chained-fault pattern: if targets stay unhealthy after fixing network, check the health check; if the site loads but a feature fails, check downstream dependencies.

Each follow-up turns this incident into prevention — the next removed rule fires an alarm immediately, and unauthorized security group edits get flagged by Config.

### Cleanup — turn off the database and destroy the environment

```bash
terraform -chdir=../../envs/sandbox apply -var="create_database=false"
```

When completely done with the course:

```bash
terraform -chdir=../../envs/sandbox destroy
```

Review the plan, type `yes`. Everything torn down, no more charges.

### The Day-2 lessons — the whole course in one

- **Real incidents have layered causes.** Fixing the first thing rarely fixes everything. Verify after every change, re-read the symptom, and don't assume resolution until you've tested the customer journey end to end.
- **One hypothesis at a time.** Changing five things at once under pressure turns one incident into three and makes it impossible to tell what worked. Isolate, fix, verify, repeat.
- **The spine scales.** The same flow from Lab 01 handles a three-fault SEV-1 — you just walk it more than once: orient → read the symptom → one hypothesis → test → fix → verify, looping on a persisting symptom.
- **Close the loop.** Every incident should leave behind an alarm, a runbook, or a guardrail so the next one is smaller. That's the climb from manual/reactive to automated/proactive.

---

## Post-incident: writing the timeline

Every incident gets a post-incident review — not to assign blame, to learn. Three sections:

1. **Timeline** — chronological log with 24-hour timestamps: when paged, what you diagnosed, what you changed, what you verified. The factual record.
2. **Root causes (blameless)** — what broke and why, without naming individuals. Describe the system conditions that allowed the failure ("we lack change control on production security groups"), not a person to blame.
3. **Follow-ups** — actions that prevent or detect this faster next time, each with an owner and a due date. Unassigned follow-ups don't get done. Every incident should generate 2-5 of them — alarms, runbooks, guardrails, Config Rules, IAM restrictions.

The faults injected and the one-shot restore commands are in the Quick reference at the end of this guide.

---

You've completed all 15 labs: monitoring, logs, compute, IAM, networking, load balancing, scaling, databases, storage, backups, patching, security, cost, and chained incidents. You've learned the triage spine, the network walk, the reach-versus-refuse fork, and verify-after-every-change.

Next: wrap up, review the one-page cheat sheet, and talk about the first 90 days on the job.

---

## Quick reference — what break.sh did & how to reset

### Faults injected (three, chained)

1. **Network** — removed the app SG's inbound rule allowing tcp/80 from the ALB SG → targets
   unhealthy (`Target.Timeout`).
2. **LB config** — changed the target-group health-check path to `/healthz` → targets *also*
   unhealthy (`Target.ResponseCodeMismatch`). **So fixing only fault 1 does not recover the site.**
3. **Database** — removed the DB SG's inbound rule allowing tcp/3306 from the app SG → once the web
   tier is healthy, `/transfer` still fails (DB unreachable).

`break.sh` also suspends the app tier's `ReplaceUnhealthy`/`AZRebalance` ASG processes before
injecting anything, so the auto-scaling group doesn't churn instances underneath you
mid-diagnosis. Resume them once the incident is verified resolved (see the restore command below).

Details + original health-check path in `.break-state.json`.

### Full one-shot restore
```bash
S=.break-state.json
aws ec2 authorize-security-group-ingress --group-id "$(jq -r .app_sg $S)" --protocol tcp --port 80 --source-group "$(jq -r .alb_sg $S)" 2>/dev/null || true
aws elbv2 modify-target-group --target-group-arn "$(jq -r .target_group_arn $S)" --health-check-path "$(jq -r .original_health_check_path $S)"
aws ec2 authorize-security-group-ingress --group-id "$(jq -r .db_sg $S)" --protocol tcp --port 3306 --source-group "$(jq -r .app_sg $S)" 2>/dev/null || true
aws autoscaling resume-processes --auto-scaling-group-name "$(jq -r .asg_name $S)" --scaling-processes ReplaceUnhealthy AZRebalance
```
