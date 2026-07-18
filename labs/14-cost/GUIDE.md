# Lab 14 — The bill jumped — find out why

FinOps for ops people. Cost is a ticket like any other, and waste hides in "available" and "unattached."

---

## Lab 14: The bill jumped — find out why

### What we'll do in this lab

- Localize the spike with Cost Explorer
- Hunt down idle Elastic IPs
- Hunt down unattached EBS volumes
- Remove the waste carefully (snapshot first if unsure)
- Set a budget so the next spike pages you instead of the invoice

### The ticket

```
Ticket:   NB-1401
Reporter: Tom (Finance) — monthly cost review
Severity: Task (monthly loop)
Title:    "The banking account's bill went up this month. Find what's driving
           it and bring it back down."
```

Cost is a ticket like any other. Tom from Finance sees the total is 40% higher than last month, but can't see what's driving it — so it lands on the platform team.

Treat it like any incident: localize it, find the driver, fix it. This is also a monthly loop task from the operating rhythm — review the bill, optimize waste, report back to Finance.

### Break the environment first

```bash
cd labs/14-cost
export AWS_REGION=us-east-1
./break.sh
```

The break script creates two classic money-wasters: an allocated-but-unattached Elastic IP, and an unattached 50 GiB EBS volume. Both tagged `Project=NorthBank` so they blend in with legitimate resources. Both cost money every hour while doing nothing.

### Step 1: Localize with Cost Explorer

Cost Explorer (in the Billing console) groups spending by service, usage type, tag, and time period.

Workflow for localizing a spike:

1. **Group by Service** — which service increased? EC2? S3? RDS?
2. **Group by Usage Type** — within that service, which usage type? Instances? Volumes? Data transfer?
3. **Filter by tag** — filter to `Project=NorthBank` to isolate one application.

Caveat: **Cost Explorer data lags about a day**, sometimes longer. For fast triage — and for this lab — hunt the wasteful resources directly instead of waiting on it.

### Step 2: Idle Elastic IPs

```bash
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==`null`].{IP:PublicIp,AllocationId:AllocationId,Tags:Tags}' \
  --output table
```

`AssociationId==null` means the IP isn't attached to an instance or network interface.

AWS charges for an Elastic IP even when it's not attached — about $0.005/hour, roughly $3.60/month, to discourage hoarding of scarce IPv4 addresses.

The list shows one unattached Elastic IP, tagged `Project=NorthBank`. Pure waste.

### Step 3: Unattached EBS volumes

```bash
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{Id:VolumeId,Size:Size,Type:VolumeType,AZ:AvailabilityZone,Tags:Tags}' \
  --output table
```

A volume with status **`available`** does not mean healthy and ready — it means **attached to nothing**.

You pay for every provisioned gigabyte regardless of attachment. A 50 GiB gp3 volume costs about $4/month; a 1 TB volume about $80/month.

The list shows one 50 GiB gp2 volume, status `available`, tagged `Project=NorthBank`, attached to nothing.

This is a common leftover: an instance gets terminated, its root volume is deleted automatically (`DeleteOnTermination=true`), but additional data volumes detach and stay around, billing every hour.

### Step 4: Remove it — carefully

Release the idle Elastic IP:

```bash
ALLOC=$(aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==`null`].AllocationId | [0]' \
  --output text)

aws ec2 release-address --allocation-id "$ALLOC"
```

Delete the unattached volume:

```bash
VOL=$(aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[0].VolumeId' --output text)

aws ec2 delete-volume --volume-id "$VOL"
```

Confirm a resource is truly unused before deleting — an `available` volume might be a data disk someone detached to resize or move, and hasn't reattached yet.

When in doubt, snapshot first:

```bash
aws ec2 create-snapshot --volume-id "$VOL" --description "Backup before deleting volume $VOL"
```

Wait for the snapshot, then delete the volume. A snapshot costs less than the volume (~$0.05/GB-month vs ~$0.08/GB-month) and gives you a safety net.

### Step 5: The other usual suspects

- **Forgotten NAT Gateways** — ~$32/month each, plus data transfer. Left running after a test environment shuts down.
  ```bash
  aws ec2 describe-nat-gateways --filter Name=state,Values=available \
    --query 'NatGateways[].{Id:NatGatewayId,Subnet:SubnetId,Tags:Tags}' --output table
  ```
- **Idle RDS databases** — a db.t3.micro is ~$15/month. Check `DatabaseConnections`; if it's been zero for weeks, stop or delete it.
- **Old snapshots** — ~$0.05/GB-month. Clean up anything past your retention policy.
  ```bash
  aws ec2 describe-snapshots --owner-ids self \
    --query 'Snapshots[].{Id:SnapshotId,Size:VolumeSize,Started:StartTime,Volume:VolumeId}' \
    --output table
  ```
- **Oversized instances** — a `c5.4xlarge` never resized down after a proof of concept. Check CloudWatch CPU; below 20% average usually means over-provisioned.
- **Left-running lab infrastructure** — forgetting `terraform destroy` after a lab keeps the ALB, NAT Gateway, and instances billing. This is why every lab emphasizes teardown and budget alarms.

### Step 6: Set a budget

Create a budget so a spike pages you instead of Finance.

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

cat > /tmp/budget.json <<'JSON'
{
  "BudgetName": "northbank-monthly-budget",
  "BudgetLimit": {
    "Amount": "100",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
JSON
```

$100/month limit — adjust to expected spend.

```bash
cat > /tmp/notif.json <<'JSON'
[{
  "Notification": {
    "NotificationType": "ACTUAL",
    "ComparisonOperator": "GREATER_THAN",
    "Threshold": 80
  },
  "Subscribers": [{
    "SubscriptionType": "EMAIL",
    "Address": "oncall@northbank.example"
  }]
}]
JSON
```

Alert at 80% of budget ($80), sent to the on-call email.

```bash
aws budgets create-budget \
  --account-id "$ACCOUNT" \
  --budget file:///tmp/budget.json \
  --notifications-with-subscribers file:///tmp/notif.json
```

Now a cost spike pages you, not Finance — before it shows up in the end-of-month report.

### Verify

```bash
aws ec2 describe-addresses --query 'Addresses[?AssociationId==`null`]' --output text
```

Empty. No idle Elastic IPs.

```bash
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[]' --output text
```

Empty. No unattached volumes.

### The Day-2 lessons

- **Cost is a ticket.** Localize, diagnose, fix, prevent — same as any incident.
- **Waste hides in "available" and "unattached."** Both cost money every hour.
- **Localize with Cost Explorer, but hunt directly for fast triage.** Cost Explorer lags a day; for immediate investigation, query resources directly.
- **Tagging makes spend findable.** `Project=NorthBank` lets you filter Cost Explorer and attribute spend by team.
- **Always confirm before deleting.** Snapshot first if unsure.
- **Budgets move you from reactive to proactive.** Without one, Finance finds the spike at month-end. With one, you're paged at 80% and fix it first.

### The monthly cost review

The monthly cost review loop:

1. **Review the bill** — compare to last month, look for spikes
2. **Localize increases** — Cost Explorer by service and usage type
3. **Hunt the waste** — query idle resources, check CloudWatch for oversized/unused
4. **Clean it up** — delete unused, resize oversized, stop idle
5. **Report** — summarize savings to Finance

---

## Quiz: Cost troubleshooting

Quick check:

- Why does an unattached Elastic IP cost money? (AWS charges for idle IPs to discourage hoarding. About $3.60 per month per idle IP.)
- What does an EBS volume's `available` status mean? (Attached to nothing. It's a floating disk. You still pay for the provisioned storage.)
- How do you localize a cost spike? (Cost Explorer: group by service → usage type → tag. Or query resources directly for fast triage.)
- Why is tagging important for cost management? (Tags let you filter spending by project or team, attribute costs, and find waste specific to one application.)
- How do budgets move you from reactive to proactive? (Without a budget, Finance finds the spike at month-end. With a budget, you get alerted at 80% and fix it immediately.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` created two classic silent money-wasters:
  1. an **allocated-but-unattached Elastic IP** (billed hourly while idle), and
  2. an **unattached 50 GiB gp2 EBS volume** (billed for provisioned storage).
- Both are tagged `Project=NorthBank` so they blend in. Details in `.break-state.json`.

### Root cause (in plain English)

- Nobody is *using* these, but AWS still bills for them.
- Idle/unattached resources are the #1 source of surprise cloud spend.
- They accumulate because deleting the *thing* (an instance) often leaves its *bits* (its EIP,
  its volume) behind.
