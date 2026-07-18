#!/usr/bin/env bash
# labs/10-s3/break.sh
#
# FAULT INJECTED: creates a bucket + a sample object, then attaches a bucket
# policy with an EXPLICIT DENY on s3:GetObject for arn:aws:s3:::<bucket>/* .
# Because an explicit Deny in a bucket policy beats any Allow (even the account
# owner's IAM allow), reading objects returns 403.
#
# WHY THIS FAULT: teaches the S3 access model + "explicit Deny wins" + the
# bucket-vs-object ARN distinction (the deny targets /*  = the objects).
#
# INTENDED DIAGNOSIS PATH:
#   aws s3 cp s3://bucket/obj -> 403  ->  get-bucket-policy shows the Deny on
#   .../*  ->  understand it targets OBJECTS  ->  remove/scope the deny.
#
# REVERSIBLE: yes. Cleanup deletes the policy + bucket. Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="northbank-statements-s3lab-${ACCOUNT_ID}-${REGION}"

echo "[break] Region: ${REGION}"
echo "[break] Bucket: ${BUCKET}"

# Create bucket (us-east-1 must not pass LocationConstraint).
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

# Put a sample object (a "statement").
echo "NorthBank statement 2026-06 - customer 12345" > /tmp/nb-statement.txt
aws s3 cp /tmp/nb-statement.txt "s3://${BUCKET}/statements/2026-06/customer-12345.txt" >/dev/null
rm -f /tmp/nb-statement.txt

# Attach the explicit-deny bucket policy (the fault). Targets .../*  = objects.
POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "NB1001AccidentalDenyReads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
JSON
)
aws s3api put-bucket-policy --bucket "${BUCKET}" --policy "${POLICY}"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "10-s3",
  "region": "${REGION}",
  "bucket": "${BUCKET}",
  "object_key": "statements/2026-06/customer-12345.txt",
  "fault": "bucket policy explicitly denies s3:GetObject on <bucket>/* (all object reads -> 403)"
}
JSON

cat <<MSG

────────────────────────────────────────────────────────────
  NB-1001  SEV-2  — reported by Marco (App team)
  "Reading statements from S3 returns 403. Worked yesterday."
────────────────────────────────────────────────────────────
  Bucket: ${BUCKET}
  Reproduce:
    aws s3 cp s3://${BUCKET}/statements/2026-06/customer-12345.txt -
  Then work the S3 access model to find the block.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Explicit-deny bucket policy attached. State in ${STATE_FILE}" >&2
