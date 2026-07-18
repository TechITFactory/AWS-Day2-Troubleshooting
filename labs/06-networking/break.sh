#!/usr/bin/env bash
# labs/06-networking/break.sh
#
# FAULT INJECTED: removes the app tier's inbound rule that allows HTTP (port 80)
# FROM the ALB security group. The ALB can no longer reach the web instances,
# so health checks fail, targets go unhealthy, and requests hang/time out.
# Instances are perfectly healthy locally -- the break is purely in the network
# path (the security group).
#
# WHY THIS FAULT: teaches the methodical path walk (SG -> NACL -> route ->
# listening) and the SG-vs-NACL model, and rewards fixing with a scoped rule
# (source = ALB SG) instead of opening 0.0.0.0/0.
#
# INTENDED DIAGNOSIS PATH:
#   target health unhealthy  ->  instances healthy locally (Lab 04 skills)  ->
#   check app SG ingress  ->  the ALB->app:80 rule is gone  ->  re-add it
#   scoped to the ALB SG.
#
# REVERSIBLE: yes. Re-authorize the exact rule (see SOLUTION / .break-state.json).
# Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${APP_SG:?Set APP_SG (terraform output app_security_group_id)}"
: "${ALB_SG:?Set ALB_SG (terraform output alb_security_group_id)}"

echo "[break] Region: ${REGION}"
echo "[break] Removing rule: allow tcp/80 to ${APP_SG} FROM ${ALB_SG}"

# Revoke the ingress rule (app SG: 80 from ALB SG). Idempotent-ish: ignore if
# it's already gone.
aws ec2 revoke-security-group-ingress \
  --region "${REGION}" \
  --group-id "${APP_SG}" \
  --protocol tcp --port 80 \
  --source-group "${ALB_SG}" >/dev/null 2>&1 || echo "[break] (rule already absent)"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "06-networking",
  "region": "${REGION}",
  "app_sg": "${APP_SG}",
  "alb_sg": "${ALB_SG}",
  "removed_rule": "ingress tcp/80 on app_sg from alb_sg",
  "fault": "ALB cannot reach app tier on port 80 (security group rule removed)"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0601  SEV-1  — reported by Marco (App team)
  "Internet banking hangs and times out. Targets unhealthy,
   but the instances themselves look fine."
────────────────────────────────────────────────────────────
  Walk the network path: SG -> NACL -> route -> is it listening?
  Find the ONE hop that's blocking traffic.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Removed ALB->app:80 ingress. State in ${STATE_FILE}" >&2
