# Lab 02 — The alarm that never fired

Two labs that pair naturally. Alarms tell you *that* something's wrong. Logs tell you *why*.

---

## Lab 02: The alarm that never fired

### What we'll do in this lab

- Read an alarm's state correctly — `INSUFFICIENT_DATA` isn't "fine"
- Find the misconfigured dimension that's making the alarm watch nothing
- Confirm the real metric is publishing data
- Rebuild the alarm with correct dimensions and a real SNS notification
- Test it by breaching the threshold on purpose and watching it fire, then clear

### The ticket

```
Ticket:   NB-0201
Reporter: Priya (Team lead) — follow-up from last week's NB-0101 outage
Severity: SEV-3 (post-incident action)
Title:    "We added an alarm after the 503 outage — but it never paged during
           the failover test. Find out why and fix it."
```

Last lab, internet banking was down for minutes before a human noticed. Priya did the right thing and added an "unhealthy hosts" alarm so it would never happen silently again.

Then the team ran a deliberate test. They made the targets unhealthy to verify the alarm would fire. And the alarm stayed green. It never paged anyone. It never changed state. It just sat there, silent, while the environment was broken.

A monitor you can't trust is worse than no monitor, because it gives you false comfort. You think you're covered, but you're not. So today isn't about "add monitoring." It's the more useful skill: why do alarms silently fail, and how do you build one you can actually trust?

### Break the environment first

```bash
cd labs/02-cloudwatch-monitoring
export ALB_ARN=$(terraform -chdir=../../envs/sandbox output -raw alb_arn)
export TG_ARN=$(terraform -chdir=../../envs/sandbox output -raw target_group_arn)
./break.sh
```

The break script creates an alarm named `northbank-unhealthy-hosts` that looks real at first glance. It's watching the `UnHealthyHostCount` metric. It's got thresholds configured. But it's subtly misconfigured in a way that makes it useless.

### Step 1: Read the alarm's state — and read it correctly

```bash
aws cloudwatch describe-alarms --alarm-names northbank-unhealthy-hosts \
  --query 'MetricAlarms[0].{State:StateValue,NS:Namespace,Metric:MetricName,Dims:Dimensions,Actions:AlarmActions}' \
  --output json
```

Look at the output carefully. The first thing everyone gets wrong: the alarm is **not** in `OK`. It's in `INSUFFICIENT_DATA`.

People glance at an alarm, see it's not red, and think "fine." It is not fine.

There are three alarm states:
- **`OK`** means "I'm watching the metric, and things are healthy."
- **`ALARM`** means "I'm watching the metric, and it breached the threshold."
- **`INSUFFICIENT_DATA`** means "I'm getting no data at all."

An alarm in `INSUFFICIENT_DATA` can never fire. It's not watching anything. It's pointing at a metric stream that doesn't exist, so it receives no data points, so it can't evaluate the threshold, so it sits in this ambiguous gray state forever.

That's already the shape of the answer: this alarm is watching nothing.

Also notice `AlarmActions` in the output. It's empty. Even if the alarm fired, it would notify no one. No SNS topic. No email. No page. Two bugs, one alarm.

### Step 2: Why is it getting no data? Check the dimensions

CloudWatch metrics have dimensions. An Application Load Balancer's `UnHealthyHostCount` metric has two dimensions: `LoadBalancer` and `TargetGroup`. An alarm watches an exact metric plus exact dimensions. If the dimensions don't match a real metric stream, you get no data.

Look at the alarm's `Dimensions` in the output. It's watching a `TargetGroup` dimension with a specific ARN suffix. Compare that against the real target group's ARN suffix:

```bash
echo "${TG_ARN##*:}"
```

This extracts the suffix after the last colon in the target group ARN. Something like `targetgroup/northbank-nonprod-tg/abc123def456`.

Now look at what the alarm is watching. It has a typo — an extra character on the end, or a digit swapped, or something subtle. The alarm is pointing at `targetgroup/northbank-nonprod-tg/abc123def456X` — a target group that doesn't exist.

That's the whole bug. A typo in a dimension doesn't throw an error. It doesn't fail the alarm creation. It just quietly points your safety net at nothing. The alarm sits in `INSUFFICIENT_DATA` forever, and you think you're covered.

### Step 3: Confirm the real metric has data

Let's verify that the metric itself is fine, and data points exist under the correct dimensions:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB --metric-name UnHealthyHostCount \
  --dimensions "Name=TargetGroup,Value=${TG_ARN##*:}" "Name=LoadBalancer,Value=${ALB_ARN##*:loadbalancer/}" \
  --start-time "$(date -u -d '-30 min' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Maximum --output table
```

You'll see data points. The metric is publishing. Data exists. The alarm was just looking in the wrong place, watching a dimension that doesn't exist.

### Step 4: Build one you can trust

Delete the broken alarm and build a correct one. Two pieces: a real notification target, and the alarm itself.

First, create an SNS topic and subscribe your email:

```bash
TOPIC_ARN=$(aws sns create-topic --name northbank-alerts --query TopicArn --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint oncall@northbank.example
```

Replace `oncall@northbank.example` with your real email address. You'll get a confirmation email. Click the link to confirm the subscription. Now the SNS topic can send you alerts.

Second, rebuild the alarm with correct dimensions and the SNS action:

```bash
aws cloudwatch put-metric-alarm --alarm-name northbank-unhealthy-hosts \
  --namespace AWS/ApplicationELB --metric-name UnHealthyHostCount \
  --statistic Maximum --period 60 --evaluation-periods 1 \
  --threshold 0 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --dimensions "Name=TargetGroup,Value=${TG_ARN##*:}" "Name=LoadBalancer,Value=${ALB_ARN##*:loadbalancer/}" \
  --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN"
```

Let's break down the key choices:

**`--threshold 0 --comparison-operator GreaterThanThreshold`** — alarm if unhealthy host count is greater than zero. Any unhealthy target triggers the alarm.

**`--evaluation-periods 1`** — alarm after one period. Don't wait for multiple periods. One minute of unhealthy targets is enough.

**`--treat-missing-data notBreaching`** — if the metric stops publishing (for example, the load balancer gets deleted), treat the missing data as "not breaching." This prevents the alarm from going into `INSUFFICIENT_DATA` and staying ambiguous. It stays in `OK` or `ALARM` — clear states.

**`--alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN"`** — notify the SNS topic when the alarm fires, and notify again when it clears. Tell people when it's over, not just when it starts. On-call needs to know when the incident resolved, not sit wondering if it's still broken.

### Step 5: Test it (the whole point)

Don't hope it works. Break the environment on purpose and watch the alarm fire. An alarm you haven't tested is a guess, not a safety net.

Scale the Auto Scaling group to zero, just like Lab 01:

```bash
export ASG_NAME=$(terraform -chdir=../../envs/sandbox output -raw asg_name)
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --min-size 0 --desired-capacity 0
```

Note: both `--min-size` and `--desired-capacity` have to move together — the Auto Scaling
group's minimum size is 2, and AWS rejects a desired capacity below the minimum on its own.

Wait about one to two minutes. The instances terminate. The targets deregister. The `UnHealthyHostCount` metric increments. The alarm evaluates the metric and sees it breached the threshold.

Check the alarm state:

```bash
aws cloudwatch describe-alarms --alarm-names northbank-unhealthy-hosts \
  --query 'MetricAlarms[0].StateValue' --output text
```

It should say `ALARM`. And you should receive an email: "ALARM: northbank-unhealthy-hosts in us-east-1." The notification works.

Now restore the environment:

```bash
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --min-size 2 --desired-capacity 2
```

Wait another minute or two. The instances launch, register with the target group, pass health checks. The metric drops back to zero. The alarm clears.

Check the state again. It should say `OK`. And you should receive another email: "OK: northbank-unhealthy-hosts in us-east-1." You get notified when it breaks, and notified when it recovers.

That's a trustworthy alarm.

### The Day-2 lesson

**`INSUFFICIENT_DATA` is a red flag, not "fine."** If you see an alarm in that state, investigate immediately. It's watching nothing.

**An alarm is only as good as its metric and dimensions.** A typo in a dimension doesn't fail loudly. It just points at nothing and sits silent forever. Always verify the dimensions match reality.

**Always wire a real notification.** An alarm with no `AlarmActions` pages nobody. It's a dashboard widget, not a safety net.

**Always test an alarm by breaching it once.** Don't assume it works. Break the environment on purpose, watch the alarm fire, verify the email lands. Only then do you know it's protecting you.

That's the maturity climb: month one, you learn you're down from a customer. Month six, the environment pages you first.

---

## Quick reference — what break.sh did & how to reset

### Fault injected

`break.sh` created a CloudWatch alarm `northbank-unhealthy-hosts` that watches
`AWS/ApplicationELB → UnHealthyHostCount` but with a **wrong `TargetGroup` dimension** (the real
target-group ARN suffix with an extra character). No metric data ever matches that dimension, so
the alarm is stuck in **`INSUFFICIENT_DATA`** and can never reach `ALARM` — it notifies no one.
It also has **no alarm action** (no SNS topic), a second, milder smell. Details in
`.break-state.json`.

### Root cause (in plain English)

- An alarm only watches the exact **metric + dimensions** you give it.
- The `TargetGroup` dimension had a typo, so it points at a target group that doesn't exist.
- No matching data → the alarm gets **no data** → it can never fire.
- A typo like this doesn't throw an error — it fails **silently**.
- The alarm looked fine (green) in the console, so nobody noticed until the failover test.

### Restore / cleanup
```bash
aws cloudwatch delete-alarms --alarm-names northbank-unhealthy-hosts
# (and optionally: aws sns delete-topic --topic-arn "$TOPIC_ARN")
```
