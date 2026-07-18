#!/usr/bin/env bash
# labs/13-security-findings/break.sh
#
# FAULT INJECTED (the REAL one): opens SSH (tcp/22) to 0.0.0.0/0 on the app
# security group. This is a genuine exposure that Security Hub / Config flag
# (e.g. "security group allows unrestricted SSH").
#
# NOISE (optional): if a GuardDuty detector exists, generate SAMPLE findings so
# the learner has to separate real exposure from sample/informational noise.
#
# WHY THIS FAULT: teaches triage -- most findings are volume, the skill is
# picking the one that matters, fixing it least-privilege, and dispositioning
# the rest with a reason.
#
# INTENDED DIAGNOSIS PATH:
#   list findings  ->  sort by severity/type  ->  identify the open-SSH finding
#   as the real exposure  ->  revoke the 0.0.0.0/0:22 rule  ->  mark samples as
#   suppressed/accepted with a note.
#
# REVERSIBLE: yes. Revoke the SSH rule (see SOLUTION). Sample findings are
# harmless and archive themselves. Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${APP_SG:?Set APP_SG (terraform output app_security_group_id)}"

echo "[break] Region: ${REGION}"
echo "[break] Opening SSH (22) to 0.0.0.0/0 on ${APP_SG}  <-- the real exposure"

aws ec2 authorize-security-group-ingress \
  --region "${REGION}" \
  --group-id "${APP_SG}" \
  --ip-permissions 'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0,Description="NB1301 accidental open SSH"}]' \
  >/dev/null 2>&1 || echo "[break] (open-SSH rule already present)"

# Optional noise: generate GuardDuty sample findings if a detector exists.
DETECTOR_ID=$(aws guardduty list-detectors --region "${REGION}" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")
if [[ -n "${DETECTOR_ID}" && "${DETECTOR_ID}" != "None" ]]; then
  echo "[break] Generating GuardDuty sample findings on detector ${DETECTOR_ID} (noise)"
  aws guardduty create-sample-findings --region "${REGION}" --detector-id "${DETECTOR_ID}" >/dev/null 2>&1 || true
else
  echo "[break] (no GuardDuty detector found; skipping sample findings -- enable GuardDuty for the full effect)"
fi

cat > "${STATE_FILE}" <<JSON
{
  "lab": "13-security-findings",
  "region": "${REGION}",
  "app_sg": "${APP_SG}",
  "guardduty_detector": "${DETECTOR_ID}",
  "real_finding": "app security group allows unrestricted SSH (0.0.0.0/0:22)",
  "noise": "GuardDuty sample findings (if detector present)"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-1301  SEV-2  — reported by Aisha (Security/GRC)
  "Security Hub is lighting up. Triage the findings, fix the
   real one, tell me which are noise."
────────────────────────────────────────────────────────────
  Start with:
    aws securityhub get-findings   (or the Security Hub console)
  Sort by severity. Find the one that's real.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Open-SSH rule added to ${APP_SG}. State in ${STATE_FILE}" >&2
