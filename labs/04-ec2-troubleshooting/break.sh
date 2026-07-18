#!/usr/bin/env bash
# labs/04-ec2-troubleshooting/break.sh
#
# FAULT INJECTED: stops and MASKS nginx on every instance in the ASG (via SSM
# Run Command). The instances stay 'running' and pass both status checks, but
# the web service is dead, so the app doesn't serve and targets go unhealthy.
# 'mask' means a normal restart won't bring it back until it's unmasked -> the
# learner has to actually investigate, not just reboot.
#
# WHY THIS FAULT: it forces the key lesson -- 'running' != 'healthy' -- and
# makes the learner get INTO the box with SSM Session Manager (no SSH key
# exists) to see the stopped service.
#
# INTENDED DIAGNOSIS PATH:
#   describe-instances (running) + describe-instance-status (checks pass)  ->
#   target health unhealthy  ->  SSM Session Manager in  ->  systemctl status
#   nginx (dead/masked)  ->  unmask + start nginx  ->  targets healthy.
#
# REVERSIBLE: yes. SOLUTION unmasks + starts nginx (or terminate the instance
# and let the ASG replace it). Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${ASG_NAME:?Set ASG_NAME (terraform output asg_name)}"

echo "[break] Region: ${REGION}"
echo "[break] ASG: ${ASG_NAME}"

# Find the instances in the ASG.
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --region "${REGION}" --auto-scaling-group-names "${ASG_NAME}" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
  --output text)

if [[ -z "${INSTANCE_IDS}" ]]; then
  echo "[break] ERROR: no InService instances found in ${ASG_NAME}." >&2
  exit 1
fi
echo "[break] Target instances: ${INSTANCE_IDS}"

# Stop + disable + mask nginx on each instance via SSM Run Command.
CMD_ID=$(aws ssm send-command \
  --region "${REGION}" \
  --document-name "AWS-RunShellScript" \
  --comment "NB-0401 fault: stop+mask nginx" \
  --instance-ids ${INSTANCE_IDS} \
  --parameters 'commands=["systemctl stop nginx","systemctl disable nginx","systemctl mask nginx"]' \
  --query 'Command.CommandId' --output text)

echo "[break] Sent SSM command ${CMD_ID}; waiting a few seconds for it to run..."
sleep 8

cat > "${STATE_FILE}" <<JSON
{
  "lab": "04-ec2-troubleshooting",
  "region": "${REGION}",
  "asg_name": "${ASG_NAME}",
  "instance_ids": "${INSTANCE_IDS}",
  "ssm_command_id": "${CMD_ID}",
  "fault": "nginx stopped, disabled and masked on all ASG instances"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0401  SEV-2  — reported by Marco (App team)
  "Web server is 'running' in EC2 but not serving. No SSH key."
────────────────────────────────────────────────────────────
  Start with:
      aws ec2 describe-instance-status --instance-ids <id>
  Then get IN with SSM Session Manager and find out why the
  app won't serve.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Instances remain 'running'; nginx is masked. State in ${STATE_FILE}" >&2
