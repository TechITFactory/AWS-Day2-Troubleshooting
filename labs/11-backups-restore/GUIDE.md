# Lab 11 — Prove the backup works (actually restore!)

Two monthly/weekly loop tasks from the operating rhythm (see docs/section-03-how-work-happens.md). Lab 11 proves a backup by actually restoring it. Lab 12 patches the fleet through a maintenance window. Both are routine work that prevents disasters.

⚠️ **Important:** Lab 11 needs the database running. Turn it on before the lab, turn it off immediately after.

---

## Lab 11: Prove the backup works (actually restore!)

### What we'll do in this lab

- Learn the backup vocabulary (RPO, RTO, snapshot, restore)
- Confirm automated backups exist and are actually running
- Restore to a new instance — never over the original
- Verify the restored data and capture evidence
- Clean up the restored resources (it's real cost)

### The ticket

```
Ticket:   NB-1101
Reporter: Aisha (Security/GRC) — monthly compliance task
Severity: Task (monthly loop)
Title:    "Audit needs evidence our banking DB backups actually work. Do a real
           restore test this month and capture the proof."
```

A backup you have never restored is not a backup — it's a hope. "Backups: enabled" and a growing pile of snapshots doesn't prove anything works. The only thing that proves it is a real restore.

Aisha wants proof, not a screenshot. So we restore one.

This isn't a break/fix incident — it's a monthly compliance task. Every month: pick a backup, restore it to a new instance, verify the data, document the results, tear it down. It doubles as audit evidence and disaster recovery practice.

### Turn the database on, then set up the restore test

The database is off by default. Turn it on:

```bash
terraform -chdir=../../envs/sandbox apply -var="create_database=true"
```

Takes 5-10 minutes. Once it's up, set up the restore test:

```bash
cd labs/11-backups-restore
export AWS_REGION=us-east-1
export DB_ID=$(terraform -chdir=../../envs/sandbox output -raw db_instance_id)
./break.sh
```

The break script confirms automated backups are enabled, then kicks off a manual snapshot to restore from. Manual snapshots take a few minutes to complete.

### What we'll do in this lab

- Confirm automated backups are enabled on the database
- Kick off a manual snapshot and wait for it to become `available`
- Restore the snapshot to a NEW instance (never over the original)
- Wait for the restored instance to come up
- Verify the data and capture evidence for the audit ticket
- Delete the restored instance and the manual snapshot (they cost real money)
- Turn the source database back off

### Step 1: The vocabulary

Define the terms first — auditors and regulators use this vocabulary.

- **Automated backups** — RDS takes daily backups plus continuous transaction logs. You set a retention period. At 7 days, RDS keeps the last 7 days and you can restore to any point in that window.
- **Retention of 0 means no automated backups at all.** Teams miss this in production — someone turns off backups to save storage cost, or Terraform gets misconfigured. Finding this in a restore test is a win: you caught it before you needed it.
- **Manual snapshots** — point-in-time backups you trigger manually. They don't expire on a schedule; you delete them yourself. Use these before major changes: schema migrations, large deletes, upgrades.
- **RPO (Recovery Point Objective)** — how much data you can afford to lose. A one-hour RPO needs at least hourly backups.
- **RTO (Recovery Time Objective)** — how long recovery is allowed to take. Today's restore test measures your real RTO.

### Step 2: Confirm backups exist, then wait for the snapshot

```bash
aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{Retention:BackupRetentionPeriod,Window:PreferredBackupWindow}' \
  --output table
```

Output:
- `Retention: 7` — automated backups enabled, kept 7 days
- `Window: 03:00-04:00` — daily backup window

Backups are configured. Wait for the manual snapshot:

```bash
SNAP_ID=$(jq -r .snapshot_id .break-state.json)
aws rds describe-db-snapshots --db-snapshot-identifier "$SNAP_ID" \
  --query 'DBSnapshots[0].{Status:Status,Progress:PercentProgress,Started:SnapshotCreateTime}' \
  --output table
```

Status shows `creating` with a progress percentage. Wait for `available`:

```bash
aws rds wait db-snapshot-available --db-snapshot-identifier "$SNAP_ID"
```

Blocks until ready. 2-5 minutes for a small database.

### Step 3: Restore to a NEW instance

The key word is **new**.

```bash
RESTORED=$(jq -r .restored_db_id .break-state.json)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$RESTORED" \
  --db-snapshot-identifier "$SNAP_ID" \
  --db-instance-class db.t3.micro \
  --no-multi-az \
  --no-publicly-accessible
```

Never restore over the original during a test — if the restore fails or the data is bad, the original stays intact. This creates a fully independent copy: same data and schema, different identifier and endpoint.

Wait for it to finish:

```bash
aws rds wait db-instance-available --db-instance-identifier "$RESTORED"
```

5-10 minutes. States go `creating` → `backing-up` → `available`.

### Step 4: Verify and capture evidence

```bash
aws rds describe-db-instances --db-instance-identifier "$RESTORED" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Size:AllocatedStorage,Created:InstanceCreateTime}' \
  --output table
```

Output:
- `Status: available`
- `Endpoint: northbank-nonprod-db-restored.abc123.us-east-1.rds.amazonaws.com`
- `Size: 20` GB
- `Created: 2026-07-03T10:15:00Z`

Available with an endpoint. For real verification, connect and check the data:

```bash
# From an instance with mysql client installed
mysql -h $RESTORED_ENDPOINT -u admin -p
```

Confirm tables exist, count rows, check recent transactions match the snapshot timestamp.

Evidence package for Aisha's ticket:
1. **Snapshot ID:** `rds:northbank-nonprod-db-2026-07-03-10-00`
2. **Snapshot timestamp:** `2026-07-03 10:00:00 UTC` — the RPO evidence. Anything after this point would be lost in a real recovery.
3. **Restore duration:** 8 minutes from `restore-db-instance-from-db-snapshot` to `available` — the measured RTO.
4. **Verification result:** connected to the restored instance, confirmed `customers`, `accounts`, `transactions` tables with expected row counts.

### Step 5: Clean up — it's real cost

A restored database is a second real bill. Delete it right away:

```bash
aws rds delete-db-instance \
  --db-instance-identifier "$RESTORED" \
  --skip-final-snapshot
```

`--skip-final-snapshot` skips RDS's default final-snapshot-on-delete — not needed for a test restore.

Delete the manual snapshot:

```bash
aws rds delete-db-snapshot --db-snapshot-identifier "$SNAP_ID"
```

Turn off the source database:

```bash
terraform -chdir=../../envs/sandbox apply -var="create_database=false"
```

### The Day-2 lessons

- **Backups only count when you've restored them.** Test them monthly, quarterly at minimum.
- **Always restore to a new instance.** Never over the original during a test.
- **Know your RPO and RTO.** RPO sets backup frequency, RTO sets restore process design. The restore test gives you the real RTO, not a guess.
- **Retention of 0 means no automated backups.** Fix it immediately — set retention to at least 7 days for production.
- **Make this a scheduled monthly habit.** Doubles as audit evidence and DR practice.

---

## Quick reference — what break.sh did & how to reset

### What `break.sh` set up

- Confirmed the source DB and its **backup retention** (days).
- Started a **manual snapshot** (`<db-id>-restoretest`) to restore from.
- No fault injected — this is a **restore test**, the point is to *do the restore*.
- Details in `.break-state.json`.
