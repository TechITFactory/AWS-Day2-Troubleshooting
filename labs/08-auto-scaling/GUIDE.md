# Lab 08 — Auto Scaling didn't heal itself

The Auto Scaling group is your safety net. It self-heals when instances die, scales up when traffic increases, scales down when traffic drops. And someone quietly unplugged it.

---

## Lab 08: Auto Scaling didn't heal itself

### What we'll do in this lab

- Spot `SuspendedProcesses` — the smoking gun for an ASG that won't self-heal
- Cross-check EC2 directly instead of trusting the group's own bookkeeping
- Read the activity history to see what the group actually did
- Understand how a forgotten suspend causes this
- Resume the suspended processes and verify the group heals

### The ticket

```
Ticket:   NB-0801
Reporter: Priya (Team lead)
Severity: SEV-2
Title:    "We lost a web instance overnight and Auto Scaling never replaced it.
           We're running below capacity and nobody got a new box."
```

Auto Scaling groups have a superpower: they self-heal. An instance dies, the group launches a replacement automatically. It's the thing that lets you sleep at night. You don't have to be on call watching dashboards waiting for an instance to fail. The group notices, launches a new one, waits for it to pass health checks, and you wake up to a healthy fleet.

So this ticket is unsettling. We lost a web server overnight. The instance terminated. And the replacement never came. We're running below capacity — one instance instead of two — and the safety net didn't catch us. No alarms fired. No errors logged. It just quietly stopped doing its job.

When self-healing stops, there's usually one quiet reason.

### Break the environment first

```bash
cd labs/08-auto-scaling
export AWS_REGION=us-east-1
export ASG_NAME=$(terraform -chdir=../../envs/sandbox output -raw asg_name)
./break.sh
```

The break script suspends the Auto Scaling group's self-healing processes — `Launch`, `Terminate`, `ReplaceUnhealthy`, `HealthCheck`, and `AZRebalance`. Then it terminates one instance directly via EC2, bypassing the group. The group now sits below its desired capacity, processes suspended, unable to heal itself.

### Step 1: Spot the smoking gun — `SuspendedProcesses`

Check the group's settings first, before you trust any capacity number:

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Running:length(Instances),Suspended:SuspendedProcesses}' \
  --output json
```

**`Desired: 2`** — the group should maintain two instances.

**`SuspendedProcesses: [...]`** — this is not empty. The list contains process names like `Launch`, `Terminate`, `ReplaceUnhealthy`, `HealthCheck`. These are the processes that make the group self-heal and scale. Someone suspended them.

There's your answer. The group is under orders to stand down. When the instance died, it did exactly what it was told: nothing.

Now look at **`Running`** — and don't be surprised if it still says `2`, with both instances listed as `Healthy`/`InService`. That's not a mistake in your command. Keep reading.

### Step 2: Don't trust the group's own bookkeeping — check EC2 directly

Here's the part that surprises people: right after `break.sh` terminates the victim instance, the ASG can keep reporting it as `InService` and `Healthy` for a while — sometimes well past when you'd expect it to notice.

Why? Because `HealthCheck` and `Terminate` are exactly the processes that would normally notice the instance is gone and update the group's bookkeeping. With both suspended, the ASG isn't just refusing to launch a replacement — it doesn't even know anything is wrong. Its own dashboard is lying to you, in perfect good faith.

Don't argue with the ASG. Go around it and ask EC2 directly:

```bash
VICTIM=$(jq -r .terminated_instance .break-state.json)
aws ec2 describe-instances --instance-ids "$VICTIM" \
  --query 'Reservations[0].Instances[0].State.Name' --output text
```

You'll see `shutting-down` or `terminated` — the instance is really gone. Compare that against the ASG still calling it `Healthy`/`InService`, and you've got the full picture: not just "no self-healing," but "no self-*awareness*." That divergence between what EC2 knows and what the ASG believes is the real smoking gun, and it's a sharper lesson than a simple capacity mismatch.

### Step 3: Read the activity history — the group's diary

The Auto Scaling group maintains an activity history. It's a timeline of every action the group took: every instance it launched, every instance it terminated, and why. This is the most underused tool in Auto Scaling troubleshooting. It's the group's diary. When you don't understand why the group did something or didn't do something, read this first.

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" \
  --max-items 10 \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Desc:Description,Cause:Cause}' \
  --output table
```

The output shows recent activities, most recent first. Normally, after an instance dies, you'd see an entry like this within a minute or two:

```
Launching a new EC2 instance: i-abc123...
StatusCode: Successful
Cause: An instance was started in response to a difference between desired and actual capacity.
```

But here? No recent launch activity. The last entry might be from hours or days ago. The gap between desired and actual capacity exists, but the group isn't acting on it.

This lines up perfectly with suspended processes. The group sees the gap, but the `Launch` process is paused, so it can't act.

### Step 4: Understand why this happens — the forgotten suspend

Suspending Auto Scaling processes is a real-world pattern. It's not a mistake. It's intentional — temporarily.

Here's the scenario: you're doing maintenance. Maybe you're deploying a new version of the app, or debugging an issue, or running a database migration that puts extra load on the instances. You don't want the Auto Scaling group to interfere during this window. You don't want it launching new instances mid-deploy, or terminating instances you're debugging, or scaling based on the unusual load pattern.

So you suspend the processes:

```bash
aws autoscaling suspend-processes --auto-scaling-group-name "$ASG_NAME"
```

You do the work. The work finishes. And then… you get distracted. A meeting. Another ticket. End of day. You forget to turn the processes back on.

A forgotten suspend is a time bomb. The group looks healthy. Desired capacity matches running capacity. Everything seems fine. But the group can't heal anymore. It goes off the next time an instance dies — maybe days or weeks later — and nobody connects it to that maintenance window from two weeks ago.

### Step 5: Fix — resume the processes

Resume all suspended processes:

```bash
aws autoscaling resume-processes --auto-scaling-group-name "$ASG_NAME"
```

The instant you run this, the group re-evaluates. It sees that desired capacity is 2, running capacity is 1, and the `Launch` process is now active. So it launches a replacement.

### Step 6: Verify — watch the group heal

Check the activity history again:

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" \
  --max-items 3 \
  --query 'Activities[].Description' --output text
```

You'll see a new entry at the top:

```
Launching a new EC2 instance: i-xyz789...
```

The group is healing itself. Watch the capacity climb back to desired:

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Running:length(Instances),InService:length(Instances[?LifecycleState==`InService`])}' \
  --output table
```

The new instance launches, registers with the target group, passes health checks, and goes into service. Running capacity returns to 2. The safety net is plugged back in.

### The Day-2 lessons

**An Auto Scaling group only self-heals if its processes are running.** When a group won't scale up, won't scale down, or won't replace failed instances, the first thing to check is `SuspendedProcesses`. If that list is not empty, that's your answer.

**The group's own dashboard can be stale — cross-check with EC2.** `describe-auto-scaling-groups` reports what the group *believes*, not necessarily current reality. If `HealthCheck` or `Terminate` are suspended, the group stops noticing instance deaths, so it can keep showing a terminated instance as `InService`/`Healthy` indefinitely. Never let a healthy-looking ASG talk you out of what `SuspendedProcesses` and `aws ec2 describe-instances` are telling you.

**Read the activity history.** It's the group's diary. It shows you exactly what the group did, when, and why — or why it did nothing. Whenever an Auto Scaling group confuses you, read this first. It almost always explains itself.

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" --max-items 20
```

**Suspending processes for maintenance is fine — just turn them back on.** Set a reminder. Document it in the change ticket. Add it to the runbook: "If you suspend processes, resume them when done." A forgotten suspend will bite you eventually.

**The mirror image: the endless replacement loop.** Remember Lab 07? A misconfigured health check marks healthy instances as unhealthy. If your Auto Scaling group is configured with `HealthCheckType = ELB`, the group trusts the load balancer's opinion. The load balancer says "this target is unhealthy," the group says "okay, I'll terminate it and launch a replacement."

The replacement comes up. The health check is still misconfigured. The load balancer marks it unhealthy. The group terminates it and launches another replacement. The cycle repeats forever. The group replaces healthy boxes in an endless loop.

Same feature — health-check-driven replacement — opposite symptom. Know both. Suspended processes mean the group won't replace anything. A bad health check means the group replaces everything constantly.

### Other common Auto Scaling issues

**Hitting the max size.** If desired capacity equals max size, the group can't scale up. Check `MaxSize` in the group configuration. If traffic increases and you need more capacity, you have to raise the max before the group can launch more instances.

**No subnets with capacity.** If the group's subnets are out of IP addresses or the availability zone is impaired, the group can't launch instances. Check the activity history for failures with reasons like "We currently do not have sufficient capacity in the Availability Zone you requested."

**Launch template or AMI issues.** If the launch template references an AMI that doesn't exist anymore, or an instance type that's not available, launches fail. The activity history will show "Failed" status with a reason.

**IAM role missing.** If the instance profile or IAM role is deleted, instances can't assume the role and the launch fails.

The activity history is the key to diagnosing all of these. It tells you what failed and why.

### Scaling policies (not covered in this lab)

This lab focuses on self-healing — maintaining desired capacity. Auto Scaling groups also support dynamic scaling policies that adjust desired capacity based on metrics:

- **Target tracking** — "keep average CPU at 50%"
- **Step scaling** — "add 2 instances when CPU > 70%, add 4 when CPU > 90%"
- **Scheduled scaling** — "scale up to 10 instances every weekday at 8am"

These policies change the desired capacity. The group then launches or terminates instances to match the new desired capacity — assuming processes aren't suspended.

Scaling policies are powerful, but they're also a common source of confusion. If desired capacity keeps changing unexpectedly, check for active scaling policies and their associated CloudWatch alarms.

---

## Quiz: Auto Scaling

Quick check:

- What do suspended processes do to self-healing? (They pause it. The group won't launch, terminate, or replace instances until processes are resumed.)
- Why might a terminated instance still show as `InService`/`Healthy` in `describe-auto-scaling-groups`? (Because `HealthCheck`/`Terminate` are suspended, so the group never notices the instance is gone — its bookkeeping goes stale. Confirm real state with `aws ec2 describe-instances`.)
- Where do you find the Auto Scaling group's activity history? (`aws autoscaling describe-scaling-activities` — shows every action the group took and why.)
- What's the health-check replacement loop risk from Lab 07? (If the health check is misconfigured and the ASG uses ELB health checks, the group will terminate healthy instances and replace them forever in a loop.)
- What's the first thing to check when a group won't scale or replace instances? (`SuspendedProcesses` — if it's not empty, processes are paused.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` **suspended** the ASG's `Launch`, `Terminate`, `HealthCheck`, `ReplaceUnhealthy`,
  and `AZRebalance` processes.
- Then it terminated one instance directly (via EC2).
- With those processes paused, the ASG **won't launch a replacement** → it sits below desired.
- Details in `.break-state.json`.

### Root cause (in plain English)

- An Auto Scaling group only self-heals if its **processes are running**.
- Someone (or some script) **suspended** them — a common thing during maintenance that never got
  turned back on.
- So when an instance died, the ASG did nothing. No error — it was told to stand down.

### Restore
```bash
aws autoscaling resume-processes --auto-scaling-group-name "$(jq -r .asg_name .break-state.json)"
```
