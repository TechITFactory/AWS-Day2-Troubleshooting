#!/usr/bin/env bash
# labs/07-load-balancer/break.sh
#
# FAULT INJECTED: changes the target group's health check PATH to /healthz,
# which the app doesn't serve (it serves /health). The app returns 404 for the
# health check, so the ALB marks every target unhealthy with reason
# 'Target.ResponseCodeMismatch' -- even though the app itself is perfectly fine.
#
# WHY THIS FAULT: it produces the same surface symptom as Lab 06 (all targets
# unhealthy) from a completely different root cause (health-check config, not
# the network). Teaches reading reason codes to tell them apart.
#
# INTENDED DIAGNOSIS PATH:
#   describe-target-health -> reason Target.ResponseCodeMismatch  ->
#   describe health-check config (path=/healthz)  ->  curl the app: /health is
#   200, /healthz is 404  ->  set path back to /health.
#
# REVERSIBLE: yes. Original path saved to .break-state.json. Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${TG_ARN:?Set TG_ARN (terraform output target_group_arn)}"

# Save the current health-check path so we can restore it.
ORIG_PATH=$(aws elbv2 describe-target-groups --region "${REGION}" --target-group-arns "${TG_ARN}" \
  --query 'TargetGroups[0].HealthCheckPath' --output text)

echo "[break] Region: ${REGION}"
echo "[break] Target group health-check path: ${ORIG_PATH}  ->  /healthz (bad)"

aws elbv2 modify-target-group \
  --region "${REGION}" \
  --target-group-arn "${TG_ARN}" \
  --health-check-path "/healthz" >/dev/null

cat > "${STATE_FILE}" <<JSON
{
  "lab": "07-load-balancer",
  "region": "${REGION}",
  "target_group_arn": "${TG_ARN}",
  "original_health_check_path": "${ORIG_PATH}",
  "fault": "health check path changed to /healthz (app serves /health) -> ResponseCodeMismatch (404)"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0701  SEV-2  — reported by Priya (Team lead)
  "ALB says all targets unhealthy, but curl on the box works."
────────────────────────────────────────────────────────────
  Start with the reason code:
    aws elbv2 describe-target-health --target-group-arn <arn>
  What is the health check actually complaining about?
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Health-check path set to /healthz. Original (${ORIG_PATH}) saved to ${STATE_FILE}" >&2
