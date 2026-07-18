#!/usr/bin/env bash
# labs/05-iam-access-denied/break.sh
#
# FAULT INJECTED: creates an S3 bucket the app should be able to use, then
# attaches an INLINE policy to the app's EC2 instance role that EXPLICITLY
# DENIES s3:PutObject on that bucket. Because an explicit Deny beats any Allow,
# the app can no longer write -> AccessDenied.
#
# WHY THIS FAULT: teaches the #1 IAM gotcha -- explicit Deny wins -- and the
# skill of reading/simulating a denial instead of blindly adding s3:*.
#
# INTENDED DIAGNOSIS PATH:
#   reproduce AccessDenied  ->  iam simulate-principal-policy (explicitDeny)  ->
#   list-role-policies / get-role-policy  ->  find the inline Deny  ->  remove it
#   (and confirm a proper least-privilege Allow exists).
#
# REVERSIBLE: yes. Deletes only the inline policy it added; bucket removed in
# cleanup. Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
: "${ROLE_NAME:?Set ROLE_NAME (terraform output instance_role_name)}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# Bucket name must be globally unique + lowercase.
BUCKET="northbank-statements-${ACCOUNT_ID}-${REGION}"
INLINE_POLICY_NAME="nb-0501-deny-statements-writes"

echo "[break] Region: ${REGION}"
echo "[break] Role:   ${ROLE_NAME}"
echo "[break] Bucket: ${BUCKET}"

# Create the bucket (idempotent-ish). us-east-1 must NOT pass LocationConstraint.
if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" >/dev/null
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
  aws s3api put-bucket-tagging --bucket "${BUCKET}" \
    --tagging 'TagSet=[{Key=Project,Value=NorthBank}]' >/dev/null || true
fi

# Attach the explicit-deny inline policy (the fault).
POLICY_JSON=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ExplicitDenyStatementWrites",
      "Effect": "Deny",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
JSON
)
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "${INLINE_POLICY_NAME}" \
  --policy-document "${POLICY_JSON}"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "05-iam-access-denied",
  "region": "${REGION}",
  "role_name": "${ROLE_NAME}",
  "bucket": "${BUCKET}",
  "inline_policy_name": "${INLINE_POLICY_NAME}",
  "fault": "explicit Deny on s3:PutObject attached to the instance role"
}
JSON

cat <<MSG

────────────────────────────────────────────────────────────
  NB-0501  SEV-2  — reported by Marco (App team)
  "App gets AccessDenied writing to its S3 bucket."
────────────────────────────────────────────────────────────
  Bucket:  ${BUCKET}
  Reproduce (from an instance via SSM, or simulate):
      echo hi > /tmp/x && aws s3 cp /tmp/x s3://${BUCKET}/x
  Then find WHY it's denied.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Inline deny '${INLINE_POLICY_NAME}' on ${ROLE_NAME}. State in ${STATE_FILE}" >&2
