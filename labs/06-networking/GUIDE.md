# Lab 06 — "The app can't reach the DB" ⭐

Two labs with the same symptom — all targets unhealthy — but different causes. Teaching them together shows you how to tell which is which in seconds.

---

## Lab 06: "The app can't reach the DB" ⭐

### What we'll do in this lab

- Confirm it's a network problem, not the app
- Check the security group first — the most common cause
- Check the network ACL only if the security group looks fine
- Check the route table
- Confirm the target is actually listening on the port

### The ticket

```
Ticket:   NB-0601
Reporter: Marco (App team)
Severity: SEV-1
Title:    "Internet banking is timing out. Requests to the app just hang, then
           fail. Network problem?"
```

The site hangs and then times out. The load balancer shows all targets as unhealthy. But the instances themselves are fine — you checked with SSM, and nginx is running. So traffic isn't reaching the app. Something in the network path is blocking it.

Networking tickets scare people. They start randomly opening ports, adding `0.0.0.0/0` rules, hoping something works. That's how you create the security findings in Lab 13.

The right approach is a checklist you walk every time, in order. Not random port-opening. A methodical path walk.

### Break the environment first

```bash
cd labs/06-networking
export AWS_REGION=us-east-1
export APP_SG=$(terraform -chdir=../../envs/sandbox output -raw app_security_group_id)
export ALB_SG=$(terraform -chdir=../../envs/sandbox output -raw alb_security_group_id)
./break.sh
```

The break script removes one inbound rule from the app security group: the rule that allows traffic from the load balancer on port 80. The load balancer can no longer reach the web instances. Health checks fail. Targets go unhealthy. Requests hang.

### Step 0: Confirm it's the network, not the app

Before you dive into security groups and route tables, split the problem. Is the app broken, or is the network blocking traffic to a working app?

Use SSM to get onto one of the instances:

```bash
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target "$INSTANCE_ID"
```

Inside the instance, curl the app locally:

```bash
curl localhost/health
```

```
OK
```

The app works locally. The instance is healthy. Nginx is serving traffic. So this is not an application problem. This is a network problem. Traffic isn't reaching the app from outside.

Exit the session. Now walk the network path in order.

### The connectivity checklist — walk in order

When traffic isn't reaching an instance, there are four things to check, in this order:

1. **Security group** — is the traffic allowed at the instance level?
2. **Network ACL** — is the traffic allowed at the subnet level?
3. **Route table** — is there a route to the destination?
4. **Is the target even listening** on that port?

Most of the time, it's the security group. Start there.

### Step 1: Check the security group

Security groups are stateful. If inbound traffic is allowed, the reply traffic is automatically allowed. You don't need separate rules for request and response. This is the key difference from network ACLs.

Check the app security group's inbound rules:

```bash
aws ec2 describe-security-groups --group-ids "$APP_SG" \
  --query 'SecurityGroups[0].IpPermissions' --output json
```

Look for a rule that allows TCP port 80 from the load balancer's security group. The rule should look like:

```json
{
  "IpProtocol": "tcp",
  "FromPort": 80,
  "ToPort": 80,
  "UserIdGroupPairs": [{
    "GroupId": "sg-abc123..."
  }]
}
```

That rule is missing. The app security group doesn't allow traffic from the ALB security group on port 80. That's the fault. The load balancer can't reach the instances, so health checks fail, so the targets go unhealthy, so customer requests hang.

### Step 2: Network ACL (only if security group looked fine)

If the security group rules looked correct, the next layer is the network ACL. NACLs are attached to subnets and control traffic at the subnet boundary.

The critical difference: **NACLs are stateless**. You must allow both the inbound request and the outbound reply. A common trap is to allow inbound traffic but forget to allow the outbound reply on ephemeral ports (1024–65535). The request gets in, the reply gets blocked, and the connection hangs.

Check the NACL:

```bash
SUBNET=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SubnetId' --output text)

aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query 'NetworkAcls[0].Entries' --output table
```

Look for rules that allow:
- **Inbound:** HTTP (port 80) from the load balancer's subnet
- **Outbound:** Ephemeral ports (1024–65535) back to the load balancer's subnet

The default NACL allows everything, so unless someone changed it, NACLs are usually not the problem. But when they are, they're hard to debug because the block is silent and stateless.

In this lab, the NACL is fine. The problem was the security group.

### Step 3: Route table

Check that the subnet has a route to the destination. For private subnets, that's usually a route to a NAT Gateway for internet access, or a route to a VPC peering connection or Transit Gateway for inter-VPC traffic.

```bash
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query 'RouteTables[0].Routes' --output table
```

In this lab, the routes are fine. The problem was the security group.

### Step 4: Is the target listening?

The last check: is the application actually listening on the port the health check is hitting? You already verified this in Step 0 when you curled `localhost/health` from inside the instance. But if you hadn't, you'd check here:

```bash
sudo netstat -tlnp | grep :80
```

This shows what's listening on port 80. If nothing is listening, the app isn't running.

### Fix — narrowest rule possible

The problem is the missing security group rule. Add it back, but scope it correctly. Don't open port 80 to `0.0.0.0/0` — that's the whole internet. Open it only to the load balancer's security group:

```bash
export APP_SG=$(terraform -chdir=../../envs/sandbox output -raw app_security_group_id)
export ALB_SG=$(terraform -chdir=../../envs/sandbox output -raw alb_security_group_id)

aws ec2 authorize-security-group-ingress \
  --group-id "$APP_SG" \
  --protocol tcp --port 80 \
  --source-group "$ALB_SG"
```

This says: allow TCP port 80 inbound to the app security group, but only from resources in the ALB security group. The load balancer can reach the app. Everything else is still blocked.

### Verify

Wait about 30 seconds for the load balancer health checks to run. Check target health:

```bash
export TG_ARN=$(terraform -chdir=../../envs/sandbox output -raw target_group_arn)
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
```

```
healthy healthy
```

Both targets are healthy. Test the front door:

```bash
export APP_URL=$(terraform -chdir=../../envs/sandbox output -raw app_url)
curl -s -o /dev/null -w '%{http_code}\n' "$APP_URL"
```

```
200
```

The site is back. Requests no longer hang. Customers can log in.

### The Day-2 lessons

**Walk the path in order.** Security group → NACL → route → is it listening. Don't jump around randomly opening ports. Work through the checklist.

**Security groups are stateful.** If inbound traffic is allowed, the reply is automatic. You don't need separate rules for requests and responses.

**Network ACLs are stateless.** You must allow both directions. This is the classic trap. Allow inbound HTTP, forget to allow outbound ephemeral ports, connection hangs.

**Fix with the narrowest rule.** Source a security group, not `0.0.0.0/0`. Opening everything to make it work is exactly what becomes a security finding in Lab 13.

**Use VPC Reachability Analyzer** (optional). This is a feature in the VPC console that traces the network path from a source to a destination and tells you exactly where traffic is blocked. You give it a source (the load balancer), a destination (an instance), and a port (80). It evaluates security groups, NACLs, routes, and tells you which hop blocks traffic. It's like the IAM policy simulator, but for networking.

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` removed the app security group's inbound rule: **allow tcp/80 from the ALB SG**.
- The ALB can no longer reach the web instances → health checks fail → targets unhealthy →
  requests hang. Details in `.break-state.json`.

### Root cause (in plain English)

- The instances are healthy; the **network path** to them is blocked.
- The specific block: the app's security group no longer lets the ALB in on port 80.
- Nothing else changed — this is one missing SG rule.

### Restore
```bash
aws ec2 authorize-security-group-ingress --group-id "$(jq -r .app_sg .break-state.json)" \
  --protocol tcp --port 80 --source-group "$(jq -r .alb_sg .break-state.json)"
```
