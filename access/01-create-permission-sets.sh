#!/usr/bin/env bash
# access/01-create-permission-sets.sh
#
# Create the "role" a NorthBank user will assume in an account. In IAM Identity
# Center, a role you can be granted is called a PERMISSION SET. Here we create
# one and attach an AWS managed policy to it.
#
# Idempotent: re-running detects the existing permission set and just ensures
# the policy is attached.
#
# Run from the management account (admin), after 00-bootstrap-NOTES.md.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

INSTANCE_ARN="$(sso_instance_arn)"
info "Identity Center instance: ${INSTANCE_ARN}"
info "Creating permission set '${NB_PERMSET_NAME}' (session ${NB_PERMSET_SESSION_DURATION})"

# ---- create (or find existing) permission set ----------------------------
PS_ARN="$(permission_set_arn "${NB_PERMSET_NAME}")"
if [[ -n "${PS_ARN}" ]]; then
  warn "Permission set '${NB_PERMSET_NAME}' already exists: ${PS_ARN} (skipping create)"
else
  PS_ARN="$(run aws sso-admin create-permission-set \
    --instance-arn "${INSTANCE_ARN}" \
    --name "${NB_PERMSET_NAME}" \
    --description "NorthBank Platform team access (created by course access/01)" \
    --session-duration "${NB_PERMSET_SESSION_DURATION}" \
    --tags "Key=Project,Value=NorthBank" "Key=ManagedBy,Value=day2-course" \
    --query 'PermissionSet.PermissionSetArn' --output text)"
  info "Created permission set: ${PS_ARN}"
fi

# ---- attach the managed policy -------------------------------------------
# create-permission-set is a no-op if the policy is already attached? No — it
# errors with ConflictException. So check first.
ALREADY_ATTACHED="$(aws sso-admin list-managed-policies-in-permission-set \
  --instance-arn "${INSTANCE_ARN}" --permission-set-arn "${PS_ARN}" \
  --query "AttachedManagedPolicies[?Arn=='${NB_PERMSET_POLICY}'].Arn" --output text)"

if [[ -n "${ALREADY_ATTACHED}" ]]; then
  warn "Managed policy already attached: ${NB_PERMSET_POLICY} (skipping)"
else
  run aws sso-admin attach-managed-policy-to-permission-set \
    --instance-arn "${INSTANCE_ARN}" \
    --permission-set-arn "${PS_ARN}" \
    --managed-policy-arn "${NB_PERMSET_POLICY}"
  info "Attached ${NB_PERMSET_POLICY}"
fi

info "Done. Permission set ARN:"
printf '%s\n' "${PS_ARN}"
echo
info "Next: ./02-create-users-groups.sh"
