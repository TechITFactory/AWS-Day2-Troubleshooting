#!/usr/bin/env bash
# labs/09-rds/break.sh
#
# FAULT INJECTED: removes the DB security group's inbound rule that allows
# MySQL (tcp/3306) FROM the app security group. The RDS instance stays
# 'Available', but the app can no longer open a connection -> connections hang
# and time out.
#
# WHY THIS FAULT: teaches the datastore triage fork -- "can't reach it"
# (timeout, network) vs "reached it, it said no" (refuse/auth). This is the
# 'reach' failure. It also reinforces that "Available" doesn't mean reachable.
#
# INTENDED DIAGNOSIS PATH:
#   symptom = timeout (not refused)  ->  RDS status Available  ->  check DB SG
#   ingress  ->  the app->db:3306 rule is gone  ->  re-add it (source = app SG).
#
# REVERSIBLE: yes. Re-authorize the exact rule (see SOLUTION). Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${DB_SG:?Set DB_SG (terraform output db_security_group_id)}"
: "${APP_SG:?Set APP_SG (terraform output app_security_group_id)}"

echo "[break] Region: ${REGION}"
echo "[break] Removing rule: allow tcp/3306 to ${DB_SG} FROM ${APP_SG}"

aws ec2 revoke-security-group-ingress \
  --region "${REGION}" \
  --group-id "${DB_SG}" \
  --protocol tcp --port 3306 \
  --source-group "${APP_SG}" >/dev/null 2>&1 || echo "[break] (rule already absent)"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "09-rds",
  "region": "${REGION}",
  "db_sg": "${DB_SG}",
  "app_sg": "${APP_SG}",
  "db_id": "${DB_ID:-unknown}",
  "removed_rule": "ingress tcp/3306 on db_sg from app_sg",
  "fault": "app cannot reach RDS on 3306 (DB security group rule removed) -> connection timeouts"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0901  SEV-1  — reported by Marco (App team)
  "App can't connect to the database. Connections hang and
   time out. RDS shows 'Available'."
────────────────────────────────────────────────────────────
  First question: is this REACH (timeout) or REFUSE (rejected)?
  Then walk the DB connection path.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Removed app->db:3306 ingress. State in ${STATE_FILE}" >&2
