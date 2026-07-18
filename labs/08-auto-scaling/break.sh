#!/usr/bin/env bash
# labs/08-auto-scaling/break.sh
#
# FAULT INJECTED: suspends the ASG's self-healing/scaling processes
# (Launch, Terminate, HealthCheck, ReplaceUnhealthy, AZRebalance), THEN
# terminates one InService instance directly via EC2. Because the ASG's
# processes are suspended, it does NOT launch a replacement -> the group sits
# below desired capacity indefinitely.
#
# WHY THIS FAULT: teaches that an ASG only self-heals if its processes are
# active, and how to read activity history + SuspendedProcesses to find why
# nothing is happening.
#
# INTENDED DIAGNOSIS PATH:
#   describe-auto-scaling-groups (Desired=2, Instances=1)  ->  SuspendedProcesses
#   is non-empty  ->  describe-scaling-activities shows nothing recent  ->
#   resume-processes  ->  ASG launches a replacement back to desired.
#
# REVERSIBLE: yes. resume-processes restores healing (see SOLUTION). Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${ASG_NAME:?Set ASG_NAME (terraform output asg_name)}"

echo "[break] Region: ${REGION}"
echo "[break] ASG: ${ASG_NAME}"

# 1) Suspend the processes that would normally heal/scale the group.
aws autoscaling suspend-processes \
  --region "${REGION}" \
  --auto-scaling-group-name "${ASG_NAME}" \
  --scaling-processes Launch Terminate HealthCheck ReplaceUnhealthy AZRebalance

# 2) Terminate one InService instance directly (EC2), NOT via the ASG API, so
#    the ASG doesn't decrement desired. With processes suspended, no replacement.
VICTIM=$(aws autoscaling describe-auto-scaling-groups --region "${REGION}" \
  --auto-scaling-group-names "${ASG_NAME}" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId | [0]' \
  --output text)

if [[ -n "${VICTIM}" && "${VICTIM}" != "None" ]]; then
  aws ec2 terminate-instances --region "${REGION}" --instance-ids "${VICTIM}" >/dev/null
  echo "[break] Terminated instance ${VICTIM}; ASG will NOT replace it (processes suspended)."
else
  echo "[break] WARN: no InService instance found to terminate." >&2
fi

cat > "${STATE_FILE}" <<JSON
{
  "lab": "08-auto-scaling",
  "region": "${REGION}",
  "asg_name": "${ASG_NAME}",
  "suspended_processes": ["Launch","Terminate","HealthCheck","ReplaceUnhealthy","AZRebalance"],
  "terminated_instance": "${VICTIM}",
  "fault": "ASG processes suspended + one instance terminated -> stays below desired capacity"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0801  SEV-2  — reported by Priya (Team lead)
  "Lost a web instance and Auto Scaling never replaced it.
   Running below capacity."
────────────────────────────────────────────────────────────
  Start with:
    aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <name>
  Why won't it heal itself?
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Processes suspended, one instance terminated. State in ${STATE_FILE}" >&2
