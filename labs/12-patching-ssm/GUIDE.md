# Lab 12 — Patch the fleet (with a maintenance window)

Two monthly/weekly loop tasks from the operating rhythm (see docs/section-03-how-work-happens.md). Lab 11 proves a backup by actually restoring it. Lab 12 patches the fleet through a maintenance window. Both are routine work that prevents disasters.

⚠️ **Important:** Lab 11 needs the database running. Turn it on before the lab, turn it off immediately after.

---

## Lab 12: Patch the fleet (with a maintenance window)

### What we'll do in this lab

- Check which instances SSM actually manages
- Walk the three SSM prerequisites in order: agent, network path, IAM role
- Reattach the missing role and confirm the instance reports in
- Scan the fleet for patch compliance
- Install patches through a maintenance window, then re-scan to prove it

### The ticket

```
Ticket:   NB-1201
Reporter: Aisha (Security/GRC) — weekly patch review
Severity: Task (weekly loop) / SEV-3
Title:    "Web servers missing critical patches, and some instances vanished
           from Systems Manager. Patch via a maintenance window."
```

The compliance report shows missing critical patches. Underneath that: two instances have vanished from Systems Manager entirely. You can't patch what you can't see — and that's today's lesson: you can't patch what you can't manage.

### Break the environment first

```bash
cd labs/12-patching-ssm
export AWS_REGION=us-east-1
export ROLE_NAME=$(terraform -chdir=../../envs/sandbox output -raw instance_role_name)
export ASG_NAME=$(terraform -chdir=../../envs/sandbox output -raw asg_name)
./break.sh
```

The break script detaches `AmazonSSMManagedInstanceCore` from the instances' IAM role. Without it, instances can't talk to Systems Manager and drop off the managed list once cached credentials expire.

### Step 1: Who's actually managed?

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{Id:InstanceId,Platform:PlatformName,PingStatus:PingStatus,LastPing:LastPingDateTime}' \
  --output table
```

This shows every instance Systems Manager can see. The web servers aren't in the list — you have to get them back under management before you can patch anything.

### Step 2: The three SSM prerequisites — check in order

An instance needs three things to be managed:

1. **The SSM agent** — a background service on the instance. Amazon Linux 2/2023, recent Ubuntu, and Windows Server AMIs ship with it pre-installed. Rarely the issue.
2. **Network connectivity** — the instance must reach the Systems Manager endpoints. A private subnet with no internet access and no VPC endpoints for SSM will block check-in. Same path-check as Lab 06: route table, security group, VPC endpoints.
3. **An IAM role with SSM permissions** — needs `AmazonSSMManagedInstanceCore` or equivalent inline permissions.

Check the role first — it's the most common failure:

```bash
aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
  --query 'AttachedPolicies[].PolicyName' \
  --output table
```

`AmazonSSMManagedInstanceCore` is missing. No permission, no management.

### Step 3: Reattach the policy and confirm

```bash
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

The agent checks in again and re-registers. Give it 2-5 minutes, then confirm:

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{Id:InstanceId,PingStatus:PingStatus}' \
  --output table
```

Web servers are back, `PingStatus: Online`.

### Step 4: Scan for compliance

Scanning is read-only — checks missing patches without installing anything.

Tag the instances into a patch group:

```bash
IDS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[].InstanceId' --output text)

aws ec2 create-tags --resources $IDS --tags Key=PatchGroup,Value=northbank-web
```

A patch group is a tag that lets you target instances without hardcoding IDs. Run the scan:

```bash
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --targets "Key=tag:PatchGroup,Values=northbank-web" \
  --parameters 'Operation=Scan' \
  --comment "Weekly compliance scan"
```

Wait a minute or two, then read the compliance state:

```bash
aws ssm describe-instance-patch-states --instance-ids $IDS \
  --query 'InstancePatchStates[].{Id:InstanceId,Missing:MissingCount,Failed:FailedCount,Installed:InstalledCount,InstalledOther:InstalledOtherCount}' \
  --output table
```

Output:
- `Missing: 12` — available but not installed
- `Failed: 0`
- `Installed: 87`

`Missing` is the compliance gap.

### Step 5: Install through a maintenance window — change control

Don't flip `Operation=Scan` to `Operation=Install` and run it mid-day. Schedule it through a **maintenance window** — a defined time, with approval, when brief disruption is acceptable. You register targets (the instances), register a task (the patching command), and set the schedule.

Create the window:

```bash
WINDOW_ID=$(aws ssm create-maintenance-window \
  --name "NorthBank-Web-Patching" \
  --schedule "cron(0 2 ? * SUN *)" \
  --duration 4 \
  --cutoff 1 \
  --allow-unassociated-targets \
  --query 'WindowId' --output text)
```

Weekly, Sunday 2am UTC, 4-hour window, 1-hour cutoff (stop launching new tasks 1 hour before the window ends).

Register the targets:

```bash
aws ssm register-target-with-maintenance-window \
  --window-id "$WINDOW_ID" \
  --target-type "INSTANCE" \
  --targets "Key=tag:PatchGroup,Values=northbank-web" \
  --name "NorthBank-Web-Servers"
```

Register the patching task:

```bash
aws ssm register-task-with-maintenance-window \
  --window-id "$WINDOW_ID" \
  --target-type "INSTANCE" \
  --targets "Key=WindowTargetIds,Values=<target-id-from-previous-command>" \
  --task-arn "AWS-RunPatchBaseline" \
  --task-type "RUN_COMMAND" \
  --priority 1 \
  --max-concurrency "50%" \
  --max-errors "0" \
  --task-invocation-parameters "RunCommand={Parameters={Operation=Install}}"
```

`MaxConcurrency=50%` patches half the fleet at a time, keeping the rest online. `MaxErrors=0` stops the window if any instance fails.

Patching now runs automatically every Sunday at 2am, in batches, logged, with failure notification. This is change control: patch on a schedule, during approved hours, not on demand.

### The Day-2 lessons

- **You can't patch what you can't manage.** Systems Manager needs agent, network path, and IAM role. Check the role first when instances disappear.
- **Scan to find the gap, install through a maintenance window to close it, re-scan to prove it.**
- **Change control is real.** Production patching goes through an approved window, never an ad hoc mid-day patch.
- **The compliance report is audit evidence.** A dashboard showing `Missing=0` across the fleet closes audit findings.
- **Patching is a weekly loop.** Scan weekly, patch in the window, report monthly.

---

## Quiz: Backups & patching

Quick check:

- Why isn't a backup real until you've restored it? (You don't know if it's corrupt, incomplete, or if the restore process works until you actually try it.)
- Why restore to a new instance during a test? (If the restore fails or the data is bad, you still have the original intact.)
- What's RPO versus RTO? (RPO = how much data loss you can tolerate, determines backup frequency. RTO = how long recovery can take, determines restore process design.)
- What are the three SSM prerequisites? (Agent installed and running, network connectivity to SSM endpoints, IAM role with SSM permissions.)
- Why patch through a maintenance window instead of on demand? (Change control — production changes go through approved windows during defined hours, not ad hoc in the middle of business day.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` **detached** `AmazonSSMManagedInstanceCore` from the web instances' IAM role.
- The SSM agent loses permission to reach Systems Manager → instances **drop off** the
  managed-instances list → they can't be inventoried or patched.
- Details in `.break-state.json`. (Allow a few minutes for cached credentials to expire.)

### Root cause (in plain English)

- The instances didn't "break" — they lost the **permission** to be managed.
- You can't patch what SSM can't see, so compliance is stuck at the first step.

### Restore
```bash
aws iam attach-role-policy --role-name "$(jq -r .role_name .break-state.json)" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```
