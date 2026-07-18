# Lab 01 — The First 5 Minutes: NorthBank is down (503)

---

## The First 5 Minutes: the triage spine

This is the most important lesson in the course — everything else builds on it.

Here's the secret: there are fifteen labs in this course, covering fifteen different AWS services. But the first five minutes are identical every time. Learn this flow and you can walk into an incident on a service you've never seen before and still look like you know what you're doing.

### The triage spine — seven steps

Every incident, every troubleshooting ticket, every alarm that fires — you work the same seven-step flow:

**Step 1: Who and where am I?**  
Confirm your identity and which account you're in before you touch anything. Run `aws sts get-caller-identity`. Read the account ID, read the assumed role. This is the habit from Section 2. Ninety percent of "why is this broken?" turns out to be "you were in the wrong account." Check first.

**Step 2: What changed?**  
This is the money question in all of operations. Systems don't usually break on their own — someone changed something. A deploy went out. A configuration changed. Someone scaled something down. Someone edited a security group. CloudTrail is the answer. Query CloudTrail for recent events and find what changed in the last hour.

**Step 3: Read the symptom at the right layer**  
Start at the front door and read inward. If customers are seeing a 503, start with the load balancer. The load balancer will point you to the target group. The target group will point you to the instances. The instances will point you to the Auto Scaling group or the security group or the IAM role. Follow the symptom layer by layer. Don't jump to random services and start poking around.

**Step 4: Form one hypothesis**  
Say it out loud before you test it. "My hypothesis is: the Auto Scaling group has zero running instances." "My hypothesis is: the security group is blocking traffic from the load balancer." One hypothesis. Not five. You're not guessing. You're forming a testable theory based on what you've read so far.

**Step 5: Test the hypothesis**  
Run one command to confirm or reject your hypothesis. Cheaply. Without making things worse. You're not changing anything yet. You're verifying that your mental model matches reality.

**Step 6: Fix — the smallest change that resolves it**  
Once you've confirmed the root cause, make the smallest change that fixes the problem. Not five changes. Not "while I'm here, let me also tweak the launch template and the health check settings." One incident, one change. Fix the thing that's broken, nothing else.

**Step 7: Verify and communicate**  
Prove recovery. Check the service is returning 200. Check the alarm cleared. Check the logs show healthy requests. Then update the ticket with the root cause, the fix, and any prevention steps. Write the handover note for the next on-call person. An incident isn't closed until it's verified and communicated.

### The discipline under pressure

Notice what you're not doing. You're not SSHing into a box and restarting services. You're not changing five things hoping one works. Under pressure, everyone wants to do something immediately — that's how you turn one incident into two.

The first five minutes are for orienting, not fixing. When you're under pressure, when it's 3am, when the CEO is asking for updates — slow down first. Run the spine. Identity, what changed, read the symptom, one hypothesis, test, fix, verify. That composure is the job.

This spine repeats in every single lab from here on. Different services, same flow. Let's apply it live.

---

## Lab 01: NorthBank is down (503)

### What we'll do in this lab

- Confirm identity and account before touching anything
- Check CloudTrail for what changed recently
- Read the symptom from the front door inward: ALB → target group → Auto Scaling group
- Form one hypothesis, test it, then apply the smallest fix
- Verify recovery and write up the incident

### The ticket

```
Ticket:   NB-0101
Reporter: Marco (App team)
Severity: SEV-1
Title:    "Customers can't reach internet banking — site returns 503"
```

It's 9:40 in the morning. Marco messages the team channel: "Internet banking is down — customers are getting a 503. Nothing changed on our side."

You open a browser to the NorthBank URL and confirm the symptom:

```bash
curl -i http://<alb-dns-name>/
```

```
HTTP/1.1 503 Service Temporarily Unavailable
```

The site is down. Customers can't log in. The clock is running. What do you do in the first five minutes?

### Break the environment first

Before we troubleshoot, we need to inject the fault. In the `labs/01-first-5-minutes` directory, there's a script called `break.sh` that deliberately breaks the environment. This simulates the real incident.

```bash
cd labs/01-first-5-minutes
export ALB_DNS=$(terraform -chdir=../../envs/sandbox output -raw app_url)
export ASG_NAME=$(terraform -chdir=../../envs/sandbox output -raw asg_name)
export TG_ARN=$(terraform -chdir=../../envs/sandbox output -raw target_group_arn)
./break.sh
```

The break script runs. The environment is now broken. The site is returning 503. Let's fix it.

> `TG_ARN` is the target group's ARN — we pull it from Terraform here so the `describe-target-health`
> command in Step 3 works. Every value the commands use comes from `terraform output`, so nothing is
> hardcoded.

### Step 1: Who and where am I?

```bash
aws sts get-caller-identity
```

This returns your user ID, account ID, and assumed role ARN. Read it. You're in the NorthBank sandbox account. You're assuming the right role. Good — you're in the right place. You're not about to make changes in production when you think you're in nonprod.

### Step 2: What changed?

This is the key question. Systems don't usually break on their own. Someone changed something. Let's check CloudTrail for recent Auto Scaling events:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=UpdateAutoScalingGroup \
  --max-results 5 \
  --query 'Events[].{Time:EventTime,User:Username,Event:EventName}' \
  --output table
```

This queries CloudTrail for any `UpdateAutoScalingGroup` calls in the recent past. And there it is — an `UpdateAutoScalingGroup` event from a few minutes ago. Somebody scaled an Auto Scaling group. You already half-suspect the cause, but you're going to confirm it by reading the symptom properly, not assume.

Note: in practice this often shows up within seconds, not the 10-15 minute worst case CloudTrail is sometimes credited with. If you don't see the event yet, no problem — the symptom will lead you to the same answer. Move on.

### Step 3: Read from the front door inward

The front door is the Application Load Balancer. A 503 response from an ALB has a specific meaning: the load balancer has no healthy targets to send requests to.

Check target health:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth' --output table
```

The output is empty. No targets are registered. Not unhealthy targets — no targets at all. The load balancer is healthy, but it has nothing to send traffic to. That's a strong clue.

### Step 4: One hypothesis, out loud

Here's a discipline to steal: say your hypothesis out loud before you test it. Don't just think it. Say it. Write it in the ticket. This forces clarity.

Hypothesis: "The Auto Scaling group has zero running instances."

One hypothesis. Not three. Not "maybe it's the security group, or maybe DNS, or maybe the launch template." One testable theory. Now test it.

### Step 5: Test the hypothesis

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:length(Instances)}' \
  --output table
```

The output shows:
- Desired capacity: 0
- Min size: 0
- Instances: 0

Hypothesis confirmed. The Auto Scaling group has zero running instances, which means zero targets registered with the load balancer, which means the ALB returns 503.

And this lines up exactly with that CloudTrail event. Someone ran an `UpdateAutoScalingGroup` call that dropped both min size and desired capacity to 0 on this Auto Scaling group. Classic mistake — they thought they were in a different environment. They meant to scale down a test environment and accidentally scaled down this one instead.

### Step 6: Fix — smallest change

Now — and only now — you fix. Restore both min size and desired capacity to 2 — note both have to move together, since AWS won't let desired capacity sit below min size:

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size 2 \
  --desired-capacity 2
```

Smallest change that resolves it. You're not also tweaking the launch template, or changing the health check settings, or doing five other things "while you're here." One incident, one change.

### Step 7: Verify and communicate

The Auto Scaling group launches two new instances. The instances register with the target group. The load balancer health checks start running.

Watch the target health change:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' \
  --output text
```

It starts as `initial`, then moves to `healthy` after about 30 seconds. Once both targets are healthy, test the front door again:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB_DNS/"
```

```
200
```

The site is back. Customers can log in. You're serving traffic again.

But you're not done. An incident isn't closed until it's verified and communicated. Update ticket NB-0101:

- **Root cause:** Someone ran an `UpdateAutoScalingGroup` call that set both min size and desired capacity to 0 on the Auto Scaling group, likely thinking they were in a different environment.
- **Fix:** Restored desired capacity to 2. Instances launched, targets went healthy, site recovered.
- **Prevention:** Limit who can modify production Auto Scaling groups. Add a CloudWatch alarm that pages immediately when target count drops below 2 (that's Lab 2).

Write a handover note: "NB-0101 resolved. ASG was scaled to zero by accident. Restored. Watch for alarm setup in Lab 2 to catch this faster next time."

### The key lessons

**"What changed?" beats "what's broken?"** Most incidents are a recent change, not a random failure. CloudTrail is your best friend.

**Always start with identity.** Who am I? Which account am I in? This prevents disasters.

**Read from the front door inward.** ALB → target group → Auto Scaling group. Layer by layer. Don't jump randomly.

**One hypothesis, out loud.** Test it before you change anything.

**Smallest fix.** Then verify. Then communicate.

That's the spine. Identity, what changed, read the symptom, hypothesis, test, fix, verify. This repeats in every lab from here on.

### One more thing

How long was internet banking down before Marco noticed and messaged the team? Minutes. Maybe five, maybe ten. That's not good enough for a bank.

We should have been paged the second those targets went unhealthy — before any human saw a 503. We need monitoring. We need alarms. We need the environment to tell us when something breaks, not wait for a customer to report it.

That's Lab 2: CloudWatch monitoring and alarms. Let's make the environment tell us next time.

---

## Quick reference — what break.sh did & how to reset

### Fault injected

`break.sh` set the Auto Scaling group's **min size and desired capacity to 0** (AWS rejects
`DesiredCapacity` below `MinSize`, so both have to move together). The ASG terminated the web
instances → they deregistered from the target group → the ALB had **no healthy targets** →
customers get **503 Service Temporarily Unavailable**. The original min size and desired
capacity are saved in `.break-state.json`.

### Root cause (in plain English)

- Someone ran an `UpdateAutoScalingGroup` call that set min size and desired capacity to 0 on
  the wrong Auto Scaling group.
- Classic mistake: they thought they were in a different account/environment.
- Nothing "failed" — a person made a change.
- This is *why* step 2 (**what changed?**) matters: the answer is a recent action, and CloudTrail records it.

### Restore
```bash
MIN=$(jq -r .original_min_size .break-state.json)
DESIRED=$(jq -r .original_desired_capacity .break-state.json)
ASG=$(jq -r .asg_name .break-state.json)
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG" --min-size "$MIN" --desired-capacity "$DESIRED"
```
