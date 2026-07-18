#!/usr/bin/env bash
# labs/02-cloudwatch-monitoring/break.sh
#
# FAULT INJECTED: creates a CloudWatch alarm 'northbank-unhealthy-hosts' that is
# subtly MISCONFIGURED — it points at a non-existent TargetGroup dimension. With
# no matching metric data, the alarm sits in INSUFFICIENT_DATA forever and never
# transitions to ALARM, so it never notifies. It LOOKS like monitoring exists.
#
# WHY THIS FAULT: the most dangerous monitoring failure isn't "no alarm" — it's
# an alarm everyone THINKS is protecting them that is silently watching nothing.
# The bug is a wrong dimension value, the single most common real-world cause.
#
# INTENDED DIAGNOSIS PATH:
#   describe-alarms (State=INSUFFICIENT_DATA)  ->  inspect Namespace/MetricName/
#   Dimensions  ->  compare against the REAL target group's ARN suffix  ->  see
#   the TargetGroup dimension doesn't match  ->  rebuild the alarm correctly.
#
# REVERSIBLE: yes. Deletes/recreates only the named alarm; original had none.
# The fix (a correct alarm) is in SOLUTION.md. Re-running is safe (idempotent).
#
# Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
ALARM_NAME="northbank-unhealthy-hosts"

: "${ALB_ARN:?Set ALB_ARN (from: terraform output alb_arn)}"
: "${TG_ARN:?Set TG_ARN (from: terraform output target_group_arn)}"

# CloudWatch's ALB dimensions use the ARN *suffix*, not the full ARN:
#   TargetGroup  = targetgroup/<name>/<id>
#   LoadBalancer = app/<name>/<id>
LB_DIM="${ALB_ARN##*:loadbalancer/}"                       # app/<name>/<id>
REAL_TG_DIM="${TG_ARN##*:}"                                # targetgroup/<name>/<id>

# The BUG: a plausible-but-wrong target group suffix (extra 'x' on the id).
BAD_TG_DIM="${REAL_TG_DIM}x"

echo "[break] Region: ${REGION}"
echo "[break] Real   TargetGroup dim: ${REAL_TG_DIM}"
echo "[break] BROKEN TargetGroup dim: ${BAD_TG_DIM}   <-- this is the injected fault"

# Create the misconfigured alarm (no SNS action either — a second, milder smell).
aws cloudwatch put-metric-alarm \
  --region "${REGION}" \
  --alarm-name "${ALARM_NAME}" \
  --alarm-description "NorthBank internet-banking unhealthy hosts (post NB-0101)" \
  --namespace AWS/ApplicationELB \
  --metric-name UnHealthyHostCount \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data missing \
  --dimensions "Name=TargetGroup,Value=${BAD_TG_DIM}" "Name=LoadBalancer,Value=${LB_DIM}"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "02-cloudwatch-monitoring",
  "alarm_name": "${ALARM_NAME}",
  "region": "${REGION}",
  "bad_target_group_dim": "${BAD_TG_DIM}",
  "real_target_group_dim": "${REAL_TG_DIM}",
  "load_balancer_dim": "${LB_DIM}",
  "fault": "alarm points at a non-existent TargetGroup dimension -> INSUFFICIENT_DATA forever, no SNS action"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0201  SEV-3  — reported by Priya (post NB-0101 action)
  "We added the 'northbank-unhealthy-hosts' alarm after the
   503 outage, but it never fired during our failover test.
   Find out why and make it trustworthy."
────────────────────────────────────────────────────────────
  Start here:
    aws cloudwatch describe-alarms --alarm-names northbank-unhealthy-hosts
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Misconfigured alarm '${ALARM_NAME}' created. State details in ${STATE_FILE}" >&2
