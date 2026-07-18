#!/usr/bin/env bash
# labs/14-cost/break.sh
#
# FAULT INJECTED: creates two classic sources of silent cloud waste:
#   1. an ALLOCATED-BUT-UNATTACHED Elastic IP (billed hourly when idle), and
#   2. an UNATTACHED gp2 EBS volume (billed for provisioned storage).
# Both are tagged Project=NorthBank so they look like they belong -- the
# learner must notice they're not actually attached to anything.
#
# WHY THIS FAULT: teaches how to hunt down waste (unattached/idle resources)
# rather than waiting a day for Cost Explorer, and reinforces tagging + budgets.
#
# INTENDED DIAGNOSIS PATH:
#   describe-addresses (find EIP with no AssociationId)  +  describe-volumes
#   (State=available = unattached)  ->  confirm unused  ->  release/delete  ->
#   create a budget so it pages next time.
#
# REVERSIBLE: yes. The fix (release EIP / delete volume) IS the cleanup.
# Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
AZ="${AWS_AZ:-${REGION}a}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"

echo "[break] Region: ${REGION} (AZ ${AZ})"

# 1) Allocate an Elastic IP and DON'T associate it (idle EIPs are billed).
ALLOC_ID=$(aws ec2 allocate-address --region "${REGION}" --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Project,Value=NorthBank},{Key=Note,Value=nb1401-waste}]' \
  --query 'AllocationId' --output text)
echo "[break] Allocated unattached Elastic IP: ${ALLOC_ID}"

# 2) Create a gp2 volume and leave it unattached (billed for storage).
VOL_ID=$(aws ec2 create-volume --region "${REGION}" --availability-zone "${AZ}" \
  --size 50 --volume-type gp2 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Project,Value=NorthBank},{Key=Note,Value=nb1401-waste}]' \
  --query 'VolumeId' --output text)
echo "[break] Created unattached 50GiB gp2 volume: ${VOL_ID}"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "14-cost",
  "region": "${REGION}",
  "unattached_eip_alloc_id": "${ALLOC_ID}",
  "unattached_volume_id": "${VOL_ID}",
  "fault": "idle Elastic IP + unattached 50GiB gp2 volume (silent monthly waste)"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-1401  TASK (monthly)  — requested by Tom (Finance)
  "The bill went up. Find the driver and bring it down."
────────────────────────────────────────────────────────────
  Hunt for waste (don't wait for Cost Explorer):
    aws ec2 describe-addresses      (idle Elastic IPs)
    aws ec2 describe-volumes        (State=available = unattached)
  Then remove it and set a budget.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. EIP ${ALLOC_ID} + volume ${VOL_ID}. State in ${STATE_FILE}" >&2
