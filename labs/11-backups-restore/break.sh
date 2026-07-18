#!/usr/bin/env bash
# labs/11-backups-restore/break.sh
#
# NOT A FAULT: this lab is a monthly RESTORE TEST, so break.sh just sets it up.
# It (1) confirms the DB exists, (2) confirms automated backups are enabled,
# and (3) kicks off a MANUAL SNAPSHOT the learner will restore from.
#
# The learner then restores that snapshot to a NEW instance, verifies it, and
# tears the restore down (see SOLUTION.md).
#
# REVERSIBLE: nothing destructive is done here. Cleanup (delete snapshot +
# restored instance) is in SOLUTION.md. Sandbox only. RDS costs money.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${DB_ID:?Set DB_ID (terraform output db_instance_id). Did you apply with create_database=true?}"

# A fixed-ish snapshot id (no timestamps allowed in scripts; use the db id).
SNAP_ID="${DB_ID}-restoretest"

echo "[break] Region: ${REGION}"
echo "[break] Source DB: ${DB_ID}"

# 1) Show backups are configured (retention must be > 0 to have automated backups).
RETENTION=$(aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${DB_ID}" \
  --query 'DBInstances[0].BackupRetentionPeriod' --output text)
echo "[break] Automated backup retention (days): ${RETENTION}"
if [[ "${RETENTION}" == "0" ]]; then
  echo "[break] WARNING: retention is 0 -> NO automated backups exist. Good talking point!" >&2
fi

# 2) Kick off a manual snapshot to restore from (async; takes several minutes).
if aws rds describe-db-snapshots --region "${REGION}" --db-snapshot-identifier "${SNAP_ID}" >/dev/null 2>&1; then
  echo "[break] Snapshot ${SNAP_ID} already exists (reusing)."
else
  aws rds create-db-snapshot --region "${REGION}" \
    --db-instance-identifier "${DB_ID}" \
    --db-snapshot-identifier "${SNAP_ID}" \
    --tags Key=Project,Value=NorthBank Key=Purpose,Value=restore-test >/dev/null
  echo "[break] Started snapshot ${SNAP_ID} (several minutes to become 'available')."
fi

cat > "${STATE_FILE}" <<JSON
{
  "lab": "11-backups-restore",
  "region": "${REGION}",
  "source_db_id": "${DB_ID}",
  "snapshot_id": "${SNAP_ID}",
  "restored_db_id": "${DB_ID}-restored",
  "backup_retention_days": "${RETENTION}",
  "task": "restore ${SNAP_ID} to a new instance, verify, capture evidence, then delete both"
}
JSON

cat <<MSG

────────────────────────────────────────────────────────────
  NB-1101  TASK (monthly)  — requested by Aisha (GRC)
  "Prove the DB backups work with a real restore test."
────────────────────────────────────────────────────────────
  Snapshot being created:  ${SNAP_ID}
  Wait until it's 'available', then restore it to a NEW
  instance (${DB_ID}-restored) and verify. Steps in SOLUTION.md.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Snapshot ${SNAP_ID} started. State in ${STATE_FILE}" >&2
