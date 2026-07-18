#!/usr/bin/env bash
# labs/12-patching-ssm/break.sh
#
# FAULT INJECTED: detaches the AmazonSSMManagedInstanceCore managed policy from
# the web instances' IAM role. Without it, the SSM agent loses permission to
# talk to Systems Manager, and the instances drop off the managed-instances
# list -> they can't be inventoried or patched.
#
# WHY THIS FAULT: the #1 real reason "my instance isn't in SSM / won't patch."
# Teaches the SSM prerequisites (agent + role + network) and the patch workflow.
#
# INTENDED DIAGNOSIS PATH:
#   describe-instance-information (instances missing)  ->  check the instance
#   role's attached policies  ->  SSM core policy is gone  ->  reattach  ->
#   instances re-register  ->  run patch scan via maintenance window.
#
# REVERSIBLE: yes. Reattach the managed policy (see SOLUTION). Sandbox only.
# NOTE: instances may take a few minutes to drop off / rejoin as cached creds
# expire and the agent re-registers.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
SSM_POLICY="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
: "${ROLE_NAME:?Set ROLE_NAME (terraform output instance_role_name)}"

echo "[break] Region: ${REGION}"
echo "[break] Detaching ${SSM_POLICY}"
echo "[break] from role ${ROLE_NAME}"

aws iam detach-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-arn "${SSM_POLICY}" 2>/dev/null || echo "[break] (policy already detached)"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "12-patching-ssm",
  "region": "${REGION}",
  "role_name": "${ROLE_NAME}",
  "detached_policy": "${SSM_POLICY}",
  "asg_name": "${ASG_NAME:-unknown}",
  "fault": "SSM core policy detached from instance role -> instances drop out of Systems Manager"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-1201  TASK/SEV-3  — requested by Aisha (GRC)
  "Web servers missing critical patches, and some instances
   vanished from Systems Manager. Patch via a maintenance
   window."
────────────────────────────────────────────────────────────
  Start with:
    aws ssm describe-instance-information
  Why aren't the instances showing up to be managed?
  (Give it a few minutes for cached credentials to expire.)
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Detached SSM core policy from ${ROLE_NAME}. State in ${STATE_FILE}" >&2
