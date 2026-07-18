# Lab 09 — The app can't connect to RDS ⭐

Two labs about access — one at the network layer, one at the policy layer.

⚠️ **Important:** Lab 09 needs the database running. Turn it on before the lab, turn it off immediately after. RDS costs real money while it's up.

---

## Lab 09: The app can't connect to RDS ⭐

### What we'll do in this lab

- Ask "reach or refuse?" first — timeout means network, rejection means capacity or credentials
- Rule out the database itself (status, metrics, events)
- Walk the network path to the database
- Fix the security group rule, scoped to the app tier
- Verify the app can connect again

### The ticket

```
Ticket:   NB-0901
Reporter: Marco (App team)
Severity: SEV-1
Title:    "Transfers are failing — the app can't connect to the database.
           Connections just hang and time out."
```

This is the same `/transfer` timeout seen in Lab 03's logs. The RDS console says the database is **Available**. It's running. But the app still can't reach it. Available and reachable are not the same thing — that's the core lesson here.

### Turn the database on, then break it

The database is off by default to save money. Turn it on:

```bash
terraform -chdir=../../envs/sandbox apply -var="create_database=true"
```

This adds an RDS MySQL instance. Takes 5-10 minutes to provision. It's the biggest cost item in the environment — a running db.t3.micro with storage costs about $15-20/month if left on. Turn it on only for labs that need it, and turn it off right after.

Once the database is available, break it:

```bash
cd labs/09-rds
export AWS_REGION=us-east-1
export DB_SG=$(terraform -chdir=../../envs/sandbox output -raw db_security_group_id)
export APP_SG=$(terraform -chdir=../../envs/sandbox output -raw app_security_group_id)
export DB_ID=$(terraform -chdir=../../envs/sandbox output -raw db_instance_id)
./break.sh
```

The break script removes the security group rule that lets the app tier reach the database on port 3306. The database is healthy and listening — the network path is blocked.

### Step 1: Reach or refuse?

Ask this before touching anything: did the connection hang, or did it get rejected?

- **Can't reach it** — connection hangs and times out. TCP never connects. This is a **network** problem: security group, missing route, wrong subnet, DNS.
- **Reached it, said no** — fast rejection: "connection refused," "authentication failed," "too many connections," "database doesn't exist." This is **credentials** or **capacity**.

Marco says it hangs. That's reach — a network problem. Go straight to security groups and routes, not passwords or connection strings.

### Step 2: Rule out the database itself

Confirm the database is healthy:

```bash
aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Engine:Engine,Size:DBInstanceClass}' \
  --output table
```

Output:
- `Status: available`
- `Endpoint: northbank-nonprod-db.abc123.us-east-1.rds.amazonaws.com`
- `Engine: mysql`
- `Size: db.t3.micro`

Status is `available`. Check the events log for recent failures or restarts:

```bash
aws rds describe-events --source-identifier "$DB_ID" \
  --source-type db-instance \
  --duration 1440 \
  --query 'Events[].{Time:Date,Message:Message}' \
  --output table
```

Duration is in minutes — 1440 = last 24 hours. Nothing alarming: routine backups, no failovers, no storage errors. The database itself is fine. Confirmed: network problem.

### Step 3: Walk the network path to the database

Same path-walk as Lab 06, aimed at the database instead of the app tier. The database sits in private subnets behind a security group; the app tier needs port 3306 (MySQL).

Check the database security group's inbound rules:

```bash
aws ec2 describe-security-groups --group-ids "$DB_SG" \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json
```

Expected: one rule allowing TCP 3306 from the app security group.

```json
{
  "IpProtocol": "tcp",
  "FromPort": 3306,
  "ToPort": 3306,
  "UserIdGroupPairs": [{
    "GroupId": "sg-abc123...",
    "Description": "Allow app tier to reach database"
  }]
}
```

That rule is missing. The database security group doesn't allow traffic from the app tier — that's the fault.

### Step 4: Fix — restore the rule, scoped

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$DB_SG" \
  --protocol tcp --port 3306 \
  --source-group "$APP_SG"
```

This allows TCP 3306 inbound to the database, only from the app security group. Everything else stays blocked.

Never open a database to `0.0.0.0/0` to fix a connection problem. Keep it in private subnets, reachable only by the app tier's security group.

### Step 5: Verify

SSM onto an app instance:

```bash
export ASG_NAME=$(terraform -chdir=../../envs/sandbox output -raw asg_name)
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target "$INSTANCE_ID"
```

Test the database connection:

```bash
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].Endpoint.Address' --output text)

nc -zv $DB_ENDPOINT 3306
```

```
Connection to northbank-nonprod-db.abc123.us-east-1.rds.amazonaws.com 3306 port [tcp/mysql] succeeded!
```

Connection succeeds. Transfers work again.

### Other RDS failures to know (not injected in this lab)

- **Too many connections** — RDS caps connections by instance size (~85 for db.t3.micro). Watch `DatabaseConnections`. Fix in the app's connection pool, not by raising the database max.
- **Storage full** — database stops accepting writes. Watch `FreeStorageSpace`. Fix: clean up data, enable storage autoscaling, or resize.
- **Failover on Multi-AZ** — primary fails, RDS switches to the standby. Same DNS endpoint, 30-60s blip. App should retry transient failures. Check `describe-events` for failover notices.
- **High CPU/memory** — watch `CPUUtilization` and `FreeableMemory`. Fix: optimize queries, add indexes, cache more, or scale up.
- **Read replica lag** — watch `ReplicaLag`. A lagging replica returns stale reads. Fix: give it more capacity.

### Cleanup — turn the database off (cost!)

```bash
terraform -chdir=../../envs/sandbox apply -var="create_database=false"
```

Destroys the RDS instance — no more charges. Turn it back on with `create_database=true` when Lab 11 or Lab 15 needs it.

### The Day-2 lessons

- **Reach vs refuse is the first question for any datastore.** Timeout = network. Rejection = capacity or credentials.
- **"Available" does not mean reachable.** RDS reports "Available" when the process is running — it doesn't check whether your app can reach it.
- **Know the vital metrics.** `DatabaseConnections`, `FreeStorageSpace`, `CPUUtilization`, `FreeableMemory`.
- **Read `describe-events` for operational history.** Failovers, restarts, backups, autoscaling, parameter changes — all logged there.
- **Keep the database in private subnets, behind a scoped security group.** Fix connection problems with the security group rule, never by making it public.

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` removed the DB security group's inbound rule: **allow tcp/3306 from the app SG**.
- RDS stays `Available`, but the app can't open a connection → **timeouts**.
- Details in `.break-state.json`.

### Root cause (in plain English)

- The database is running fine. The app just **can't reach it on the network**.
- The DB's security group no longer lets the app tier in on port 3306.
- "Available" only means the DB engine is up — not that anyone can connect.
