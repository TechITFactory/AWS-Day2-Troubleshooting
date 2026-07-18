# Lab 04 — Instance is "running" but the app won't serve

---

## Lab 04: Instance is "running" but the app won't serve

### What we'll do in this lab

- Check EC2 status checks, not just instance state
- Confirm the app itself is down, not just the box
- Connect without SSH using SSM Session Manager
- Find the dead service on the instance
- Decide: fix in place or replace the instance

### The ticket

```
Ticket:   NB-0401
Reporter: Marco (App team)
Severity: SEV-2
Title:    "A web server shows healthy in EC2 but it's not serving pages — and
           I don't have an SSH key to get in and look."
```

This is a confusing ticket. Marco opens the EC2 console, sees the instance state is `running`, sees two green checkmarks next to the status checks, and thinks "the server is fine." But customers are getting errors. The load balancer says the target is unhealthy. The app isn't serving traffic.

And there's no SSH key. The launch template doesn't have a key pair configured. Marco can't just SSH in and poke around. So how do you troubleshoot an instance when the console says it's healthy but the app clearly isn't working?

### The key insight: running is not healthy

Here's the fundamental confusion about EC2 instance state. When the console says `running`, it only means **the virtual machine booted**. That's it. The hypervisor started the VM, the operating system loaded, and the instance reached a running state.

`running` says nothing about your application. It doesn't know if nginx is running. It doesn't know if your app process started. It doesn't know if the disk is full or the configuration is broken. It just knows the VM is on.

**`running` is not `healthy`.** This is the lesson that trips up everyone at least once.

### Break the environment first

```bash
cd labs/04-ec2-troubleshooting
export AWS_REGION=us-east-1
export ASG_NAME=$(terraform -chdir=../../envs/sandbox output -raw asg_name)
./break.sh
```

The break script uses SSM Run Command to stop, disable, and mask the nginx service on every instance in the Auto Scaling group. The instances are still running. The OS is fine. But the web service is dead.

### Step 1: Check the status checks, not just the state

There are two EC2 status checks, and most people don't know what they mean:

**System status check** — this checks AWS's hardware and network. Is the physical host healthy? Is network connectivity working? If this fails, it's AWS's problem. You open a support case or wait for AWS to resolve it. You can't fix it yourself.

**Instance status check** — this checks the operating system. Did the OS boot correctly? Is the kernel responding? Is the instance reachable? If this fails, it's your problem. The OS is broken, the instance is frozen, or the network configuration inside the guest is wrong.

Get the instance ID from the Auto Scaling group:

```bash
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)
```

Now check the instance status:

```bash
aws ec2 describe-instance-status --instance-ids "$INSTANCE_ID" \
  --query 'InstanceStatuses[0].{State:InstanceState.Name,System:SystemStatus.Status,Instance:InstanceStatus.Status}' \
  --output table
```

The output shows:
- `State: running`
- `System: ok`
- `Instance: ok`

Both status checks are green. The VM is fine. The hardware is fine. The OS is fine. So the problem is **inside** the box — at the application layer. EC2 can't see it.

### Step 2: Confirm the app is actually down

Check the target health from the load balancer's perspective:

```bash
export TG_ARN=$(terraform -chdir=../../envs/sandbox output -raw target_group_arn)
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth' --output table
```

The target is `unhealthy`. The reason is `Target.Timeout` or `Target.FailedHealthChecks`. The load balancer tried to reach the health check endpoint on the instance and got no response. The app isn't serving traffic.

So we have an instance that EC2 thinks is healthy, but the load balancer knows is broken. The problem is the application, not the infrastructure.

### Step 3: Get inside without SSH — SSM Session Manager

There's no SSH key configured. Port 22 is closed in the security group. This is deliberate. Modern operations doesn't use SSH keys for fleet management. You use **AWS Systems Manager Session Manager**.

Session Manager gives you an interactive shell on an instance through the Systems Manager agent, without opening port 22, without managing SSH keys, without a bastion host. Every session is logged to CloudTrail and optionally to S3 or CloudWatch Logs. It's fully audited.

The launch template includes an IAM instance role with the `AmazonSSMManagedInstanceCore` managed policy. That's all you need. The instance registers with Systems Manager automatically when it boots.

Start a session:

```bash
aws ssm start-session --target "$INSTANCE_ID"
```

This opens an interactive shell on the instance. You're in. No key required.

### Step 4: Find the dead service

Inside the instance, check the nginx service:

```bash
systemctl status nginx
```

The output shows:
```
● nginx.service
   Loaded: masked (/dev/null; bad)
   Active: inactive (dead)
```

The service is **masked**. In systemd, masking a service means it's completely disabled and linked to `/dev/null`. You can't start it with a simple `systemctl start`. This forces you to explicitly unmask it first — it's a way to prevent a service from starting accidentally.

Try to hit the app locally:

```bash
curl localhost/
```

```
curl: (7) Failed to connect to localhost port 80: Connection refused
```

Nothing is listening on port 80. The web service is completely stopped.

### Step 5: Fix in place or replace?

You have two options here. This is a judgment call you'll make under pressure in real incidents.

**Option A: Fix in place** — fastest when you trust the instance is otherwise healthy and you just need to restart a service:

```bash
sudo systemctl unmask nginx
sudo systemctl enable --now nginx
curl localhost/health
```

This unmasks the service, enables it so it starts on boot, and starts it immediately. The app comes back up. Test locally — the health check endpoint returns `OK`. Exit the session. Wait 30 seconds for the load balancer health checks to pass. The target goes healthy. The site serves traffic.

This is fast. You're back in under a minute.

**Option B: Replace the instance** — cleaner when you don't fully trust the instance, when you suspect it might be compromised or corrupted, or when you're in a "cattle not pets" infrastructure model:

Exit the session. From your workstation:

```bash
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id "$INSTANCE_ID" \
  --should-decrement-desired-capacity false
```

The `--should-decrement-desired-capacity false` flag is critical. It tells the Auto Scaling group: terminate this instance, but don't reduce the desired capacity. Launch a replacement immediately.

The ASG terminates the bad instance and launches a fresh one from the launch template. The new instance boots, nginx starts automatically from the user data script, registers with the target group, passes health checks. You're back in two to three minutes.

This is slower, but it's a clean slate. The new instance has no history, no leftover state, no mystery changes someone might have made. If you grab the logs from the old instance first (via CloudWatch or SSM), you lose nothing important. The logs are preserved, and the bad instance is gone.

### The trade-off

**Fix in place** when:
- The failure cause is obvious and simple (a stopped service, a full disk you can clean)
- You trust the instance is otherwise healthy
- Speed matters more than cleanliness
- You need to preserve local state or logs that aren't shipped elsewhere

**Replace** when:
- You don't fully trust the instance (potential compromise, corruption, mystery changes)
- You're running immutable infrastructure (cattle not pets)
- The Auto Scaling group can quickly launch a replacement
- Logs are already shipped to CloudWatch, so there's nothing local you need

In a mature environment with good logging and immutable infrastructure, replace is often the default. It's the clean answer. But fix-in-place is sometimes the right move when you're under pressure and you just need the site back up immediately.

### Verify

After either fix, verify the target health:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' \
  --output text
```

It should say `healthy`. And test the front door:

```bash
export APP_URL=$(terraform -chdir=../../envs/sandbox output -raw app_url)
curl -s -o /dev/null -w '%{http_code}\n' "$APP_URL"
```

```
200
```

The site is back. The load balancer is routing traffic. Customers can log in.

Update the ticket:
- **Root cause:** nginx service was stopped and masked. Instance state was `running` and status checks passed, but the application wasn't serving.
- **Fix:** Unmasked and started nginx (or replaced the instance with a healthy one).
- **Lesson:** `running` does not mean `healthy`. Always check target health and application status, not just instance state.

### The Day-2 lessons

**`running` is not `healthy`.** EC2 instance state only tells you the VM booted. It says nothing about your application. Always check the status checks and the actual application health.

**Learn the two status checks:**
- **System status** = AWS's hardware and network. If it fails, AWS fixes it or you migrate the instance.
- **Instance status** = your OS. If it fails, you troubleshoot the guest OS or replace the instance.

**SSM Session Manager replaces SSH.** No keys to manage. No port 22 to leave open. No bastion hosts to maintain. Fully logged and audited. This is the modern way to get a shell on an instance.

**Fix in place or replace** is the big decision under pressure. In a cattle-not-pets world, replacing is often the right, clean answer. But know when fix-in-place is faster and safe enough.

---

## Quiz: EC2 health

Quick check:

- What does `running` instance state mean? (The VM booted. Says nothing about your application.)
- What are the two EC2 status checks? (System status = AWS's infrastructure; instance status = your OS.)
- Why use SSM Session Manager instead of SSH? (No keys to manage, no port 22 open, fully logged and audited.)
- When do you fix in place versus replace an instance? (Fix in place: fast, when you trust the box. Replace: clean slate, when you don't trust it or run immutable infrastructure.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` used SSM Run Command to **stop, disable, and mask nginx** on every ASG instance.
- The instances are still `running` and pass status checks — only the *app* is down.
- "Masked" means a plain `systemctl start` is refused until you `unmask` it (forces real
  investigation). Details in `.break-state.json`.

### Root cause (in plain English)

- The VM is fine. The **web service** on it was stopped.
- EC2 reports `running` because the machine booted — it has no idea nginx died.
- This is the whole lesson: **`running` ≠ `healthy`.**

### Restore
```bash
# Reapply Option A to all instances via SSM, or simplest: terminate the instances
# and let the ASG rebuild from the (clean) launch template:
aws autoscaling terminate-instance-in-auto-scaling-group --instance-id "$INSTANCE_ID" \
  --should-decrement-desired-capacity false
```
