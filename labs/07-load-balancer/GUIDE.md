# Lab 07 — All targets unhealthy (but the app is fine)

Two labs with the same symptom — all targets unhealthy — but different causes. Teaching them together shows you how to tell which is which in seconds.

---

## Lab 07: All targets unhealthy (but the app is fine)

### What we'll do in this lab

- Read the target health reason code, not just "unhealthy"
- Tell network (`Target.Timeout`) apart from configuration (`Target.ResponseCodeMismatch`)
- Check the health check's path, port, and matcher
- Confirm what the app actually serves, via SSM
- Fix the health check (or the app) so they agree

### The ticket

```
Ticket:   NB-0701
Reporter: Priya (Team lead)
Severity: SEV-2
Title:    "The ALB says every target is unhealthy, but I can curl the app on
           the instances directly and it works. What's going on?"
```

This looks identical to Lab 06. The load balancer says all targets are unhealthy. The site is down — 503. But when Priya SSHs to an instance and curls the app locally, it works fine. Nginx is running. The app is serving traffic. The health check is failing, but the app is healthy.

Same symptom as Lab 06, different cause. This is the lesson: how to tell which in seconds.

### Break the environment first

```bash
cd labs/07-load-balancer
export AWS_REGION=us-east-1
export TG_ARN=$(terraform -chdir=../../envs/sandbox output -raw target_group_arn)
./break.sh
```

The break script changes the target group's health check path from `/health` to `/healthz`. The app doesn't serve `/healthz`. It returns 404. The load balancer expects 200, sees 404, and marks every target unhealthy.

### The key skill: read the reason code

Check target health, but this time look at the full output including the reason:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Desc:TargetHealth.Description}' \
  --output table
```

The output shows:
- `State: unhealthy`
- `Reason: Target.ResponseCodeMismatch`

That reason code is the diagnosis. Each reason code points to a different problem:

**`Target.Timeout`** — the load balancer couldn't connect to the target at all. The connection timed out. This is a network problem. The security group is blocking traffic, or the NACL is blocking traffic, or the route is missing. This was Lab 06.

**`Target.ResponseCodeMismatch`** — the load balancer connected to the target fine. The TCP connection succeeded. But the HTTP response code didn't match what the health check expected. The load balancer expected 200, got 404 (or 500, or 302). This is a configuration problem. Either the health check is pointed at the wrong path, or the health check matcher is set to the wrong code, or the app is returning the wrong code. This is Lab 07.

**`Target.FailedHealthChecks`** — generic failure. The target failed the health check for some reason. Look at the description for more detail.

The reason code tells you which direction to go. `Timeout` means network. `ResponseCodeMismatch` means health check configuration or application code.

### Check the health check configuration

Look at the target group's health check settings:

```bash
aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" \
  --query 'TargetGroups[0].{Path:HealthCheckPath,Port:HealthCheckPort,Matcher:Matcher.HttpCode,Protocol:HealthCheckProtocol,Interval:HealthCheckIntervalSeconds,Timeout:HealthCheckTimeoutSeconds,Healthy:HealthyThresholdCount,Unhealthy:UnhealthyThresholdCount}' \
  --output table
```

The key settings:
- **Path:** `/healthz` — this is what the load balancer is requesting
- **Port:** `traffic-port` — same port as the target receives traffic on (80)
- **Matcher:** `200` — the load balancer expects HTTP 200
- **Protocol:** `HTTP`

The health check is asking for `/healthz`. That's suspicious. Most apps serve health checks on `/health`, `/healthcheck`, or `/`.

### Confirm what the app actually serves

SSM onto an instance and test both paths:

```bash
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target "$INSTANCE_ID"
```

Inside the instance:

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost/health
```

```
200
```

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost/healthz
```

```
404
```

There it is. `/health` returns 200. `/healthz` returns 404. The health check is pointed at a path that doesn't exist. The app is perfectly healthy, but the load balancer thinks it's broken because the health check is misconfigured.

### Fix — make the check and the app agree

You have two options:

**Option A: Fix the health check** — point it back at the path the app actually serves:

```bash
aws elbv2 modify-target-group --target-group-arn "$TG_ARN" --health-check-path /health
```

**Option B: Fix the app** — make the app serve the path the health check is asking for. Add a `/healthz` endpoint that returns 200.

The point is to make the health check and the app agree. Fix whichever is wrong. In this case, the health check configuration changed (someone edited it by mistake, or a Terraform apply reverted it), so we fix the health check.

### Verify

Wait about 30 seconds for health checks to pass:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
```

```
healthy healthy
```

Test the front door:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "$APP_URL"
```

```
200
```

The site is back.

### The Day-2 lessons

**The reason code is the diagnosis.** `Timeout` = network problem (Lab 06). `ResponseCodeMismatch` = configuration problem (Lab 07). Read the reason code first and you know which direction to go. Don't waste time checking security groups when the reason code says `ResponseCodeMismatch` — the connection succeeded, the problem is the HTTP response.

**A health check has to agree with the app.** Right path, right port, right expected code (matcher). One wrong setting fails perfectly healthy instances.

**"All targets unhealthy" can be network or health check.** Same symptom, different cause. The reason code tells you which.

**Beware the feedback loop with Auto Scaling.** If your Auto Scaling group is configured with ELB health checks, and the health check is misconfigured, the ASG will see healthy instances marked unhealthy and terminate them. It launches replacements, the health check fails them too, and it terminates them. The ASG replaces healthy boxes forever in a loop. That's Lab 08.

### Other health check settings that matter

**Matcher:** The expected HTTP response code. Default is 200, but you can set it to `200-299` to accept any 2xx code, or `200,301` to accept multiple specific codes.

**Interval:** How often the health check runs. Default is 30 seconds. Lower means faster detection, but more load on the targets.

**Timeout:** How long to wait for a response. Default is 5 seconds. If the app takes longer than this to respond, the health check fails.

**Healthy threshold:** How many consecutive successful health checks before marking a target healthy. Default is 2 or 5 depending on the load balancer type.

**Unhealthy threshold:** How many consecutive failed health checks before marking a target unhealthy. Default is 2.

All of these can cause health check failures if misconfigured. The path and matcher are the most common culprits.

---

## Quiz: SGs, NACLs & target health

Quick check:

- What's the difference between security groups and network ACLs? (Security groups are stateful — reply traffic is automatic. NACLs are stateless — you must allow both directions.)
- What order do you walk the network path? (Security group → NACL → route table → is the target listening.)
- What does `Target.Timeout` mean? (Couldn't connect at all — network problem.)
- What does `Target.ResponseCodeMismatch` mean? (Connected fine, but got the wrong HTTP code — health check configuration or app problem.)
- Why not just open port 80 to `0.0.0.0/0`? (It works, but it's overly permissive, fails audits, creates security findings. Scope to the source security group instead.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` changed the target group's **health-check path** from `/health` to `/healthz`.
- The app doesn't serve `/healthz`, so it returns **404** to the health check.
- The ALB marks every target unhealthy with **`Target.ResponseCodeMismatch`**.
- Original path saved in `.break-state.json`.

### Root cause (in plain English)

- The app is healthy. The **health check is asking for the wrong page**.
- `/healthz` returns 404; the ALB expects a `200`, so it fails every instance.
- The instances get replaced or drained even though nothing is wrong with them.

### Restore
```bash
aws elbv2 modify-target-group --target-group-arn "$(jq -r .target_group_arn .break-state.json)" \
  --health-check-path "$(jq -r .original_health_check_path .break-state.json)"
```
