#!/usr/bin/env bash
# labs/15-incident-sim/break.sh
#
# CAPSTONE: injects THREE chained faults so no single check explains the whole
# incident (like a real SEV-1):
#   FAULT 1 (network):     remove app<-ALB ingress on tcp/80  -> targets unhealthy
#   FAULT 2 (LB config):   set health-check path to /healthz  -> ALSO unhealthy
#                          (so fixing only fault 1 does NOT bring targets back)
#   FAULT 3 (database):    remove db<-app ingress on tcp/3306 -> after web is
#                          healthy, /transfer still fails (DB unreachable)
#
# WHY CHAINED: teaches that real incidents have layered causes; you must isolate
# and fix each, verifying between steps, not guess.
#
# ASG note: the app tier's ASG uses health_check_type=ELB, so once targets start
# failing the injected health check it will terminate and replace them on its
# own timeline. The replacements land in the exact same broken state (the fault
# is still live), so this just churns forever and makes the front-door symptom
# flicker between a clean 503 (no healthy targets) and an intermittent 504 (ALB
# forwarded to a target that was still mid-replacement/draining and it timed
# out) depending on when you happen to curl. Real on-call move: pause the
# automation that's fighting your diagnosis. We suspend ReplaceUnhealthy/
# AZRebalance here and resume them once the incident is verified resolved (see
# SOLUTION.md's one-shot restore, and Phase 4 of the capstone doc).
#
# REVERSIBLE: yes. SOLUTION.md gives the exact unwind for all three, plus
# resuming the ASG processes. Sandbox only. Requires create_database=true for
# FAULT 3 to matter.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${APP_SG:?Set APP_SG (terraform output app_security_group_id)}"
: "${ALB_SG:?Set ALB_SG (terraform output alb_security_group_id)}"
: "${DB_SG:?Set DB_SG (terraform output db_security_group_id)}"
: "${TG_ARN:?Set TG_ARN (terraform output target_group_arn)}"
: "${ASG_NAME:?Set ASG_NAME (terraform output asg_name)}"

echo "[break] Region: ${REGION}"

# Save the original health-check path before we change it.
ORIG_HC_PATH=$(aws elbv2 describe-target-groups --region "${REGION}" --target-group-arns "${TG_ARN}" \
  --query 'TargetGroups[0].HealthCheckPath' --output text)

echo "[break] Pausing ASG auto-replacement (${ASG_NAME}) so it doesn't churn instances mid-incident"
aws autoscaling suspend-processes --region "${REGION}" \
  --auto-scaling-group-name "${ASG_NAME}" \
  --scaling-processes ReplaceUnhealthy AZRebalance

echo "[break] FAULT 1: remove ALB->app:80 ingress on ${APP_SG}"
aws ec2 revoke-security-group-ingress --region "${REGION}" \
  --group-id "${APP_SG}" --protocol tcp --port 80 --source-group "${ALB_SG}" \
  >/dev/null 2>&1 || echo "[break]   (already absent)"

echo "[break] FAULT 2: break health-check path (${ORIG_HC_PATH} -> /healthz)"
aws elbv2 modify-target-group --region "${REGION}" \
  --target-group-arn "${TG_ARN}" --health-check-path "/healthz" >/dev/null

echo "[break] FAULT 3: remove app->db:3306 ingress on ${DB_SG}"
aws ec2 revoke-security-group-ingress --region "${REGION}" \
  --group-id "${DB_SG}" --protocol tcp --port 3306 --source-group "${APP_SG}" \
  >/dev/null 2>&1 || echo "[break]   (already absent)"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "15-incident-sim",
  "region": "${REGION}",
  "app_sg": "${APP_SG}",
  "alb_sg": "${ALB_SG}",
  "db_sg": "${DB_SG}",
  "target_group_arn": "${TG_ARN}",
  "asg_name": "${ASG_NAME}",
  "original_health_check_path": "${ORIG_HC_PATH}",
  "suspended_asg_processes": ["ReplaceUnhealthy", "AZRebalance"],
  "faults": [
    "1 network: ALB->app:80 ingress removed",
    "2 lb-config: health-check path -> /healthz",
    "3 database: app->db:3306 ingress removed"
  ]
}
JSON

cat <<'MSG'

════════════════════════════════════════════════════════════
  NB-1501  SEV-1  — PAGED (you are on-call)
  "Internet banking is DOWN. Customers can't log in or move
   money. The clock is running."
════════════════════════════════════════════════════════════
  This one has MORE THAN ONE cause. Work the triage spine,
  fix one thing at a time, and VERIFY between each fix.
    curl -i http://<alb-dns-name>/
════════════════════════════════════════════════════════════
MSG

echo "[break] Done. 3 faults injected. Full timeline in SOLUTION.md. State in ${STATE_FILE}" >&2
