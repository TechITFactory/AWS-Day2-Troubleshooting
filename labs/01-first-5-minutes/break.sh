#!/usr/bin/env bash
# labs/01-first-5-minutes/break.sh
#
# FAULT INJECTED: sets the web-app Auto Scaling group's desired capacity to 0.
# The ASG terminates the instances, they deregister from the target group, and
# the ALB — with no healthy targets — returns 503 to customers.
#
# WHY THIS FAULT: it's the perfect "first 5 minutes" teacher. The symptom is a
# blunt 503 at the front door, and the root cause is a single, recent, visible
# API call (UpdateAutoScalingGroup) that CloudTrail records — so step 2 of the
# triage spine, "what changed?", pays off directly.
#
# INTENDED DIAGNOSIS PATH:
#   sts get-caller-identity  ->  curl ALB (503)  ->  describe-target-health
#   (no healthy targets)  ->  describe-auto-scaling-groups (Desired=0, Min=0)  ->
#   CloudTrail LookupEvents for UpdateAutoScalingGroup (who/when)  ->  set it back.
#
# REVERSIBLE: yes. The original min size and desired capacity are saved to
# .break-state.json; the fix is `aws autoscaling update-auto-scaling-group
# --min-size <n> --desired-capacity <n>` (see SOLUTION.md). Re-running is safe.
#
# Sandbox only. Never run against a real environment.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"

: "${ASG_NAME:?Set ASG_NAME (from: terraform output asg_name)}"

echo "[break] Region: ${REGION}"
echo "[break] Target ASG: ${ASG_NAME}"

# Capture current desired/min capacity so we (and the SOLUTION) can restore them.
read -r CURRENT_MIN CURRENT_DESIRED <<<"$(aws autoscaling describe-auto-scaling-groups \
  --region "${REGION}" \
  --auto-scaling-group-names "${ASG_NAME}" \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity]' --output text)"

if [[ -z "${CURRENT_DESIRED}" || "${CURRENT_DESIRED}" == "None" ]]; then
  echo "[break] ERROR: ASG '${ASG_NAME}' not found in ${REGION}." >&2
  exit 1
fi

# Record instructor state (NOT shown to the learner).
cat > "${STATE_FILE}" <<JSON
{
  "lab": "01-first-5-minutes",
  "asg_name": "${ASG_NAME}",
  "region": "${REGION}",
  "original_min_size": ${CURRENT_MIN},
  "original_desired_capacity": ${CURRENT_DESIRED},
  "fault": "set min size and desired capacity to 0"
}
JSON

# Inject the fault. MinSize must drop with it -- AWS rejects DesiredCapacity
# below MinSize -- so this is one update-auto-scaling-group call, not
# set-desired-capacity alone.
aws autoscaling update-auto-scaling-group \
  --region "${REGION}" \
  --auto-scaling-group-name "${ASG_NAME}" \
  --min-size 0 --desired-capacity 0 >/dev/null

# ---- what the LEARNER sees (clean symptom only) --------------------------
cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0101  SEV-1  — reported by Marco (App team)
  "Customers can't reach internet banking — site returns 503."
────────────────────────────────────────────────────────────
  Reproduce it:
      curl -i http://<alb-dns-name>/
  Then work the First 5 Minutes triage spine. Good luck.
────────────────────────────────────────────────────────────
MSG

# Instructor breadcrumb (stderr, so it's easy to hide when recording).
echo "[break] Done. Original desired=${CURRENT_DESIRED} saved to ${STATE_FILE}" >&2
echo "[break] Instances will terminate; targets go unhealthy within ~30-60s." >&2
