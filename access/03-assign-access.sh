#!/usr/bin/env bash
# access/03-assign-access.sh
#
# The actual GRANT. An account assignment ties three things together:
#     GROUP  +  PERMISSION SET  +  ACCOUNT
# i.e. "members of NorthBank-Platform may assume NorthBankPowerUser in account X."
# This is what makes a tile appear in the SSO portal.
#
# Idempotent: create-account-assignment is safe to re-run (AWS treats an
# identical assignment as already-provisioned), but we check first to keep the
# on-camera output clean.
#
# Run from the management account (admin).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

INSTANCE_ARN="$(sso_instance_arn)"

# Which account to grant into. Default: the account we're currently in
# (the sandbox simplification — one account instead of five).
TARGET_ACCOUNT="${NB_ACCOUNT_ID:-$(current_account_id)}"

PS_ARN="$(permission_set_arn "${NB_PERMSET_NAME}")"
[[ -n "${PS_ARN}" ]] || die "Permission set '${NB_PERMSET_NAME}' not found. Run ./01-create-permission-sets.sh first."

GID="$(group_id "${NB_GROUP}")"
[[ -n "${GID}" ]] || die "Group '${NB_GROUP}' not found. Run ./02-create-users-groups.sh first."

info "Granting: group '${NB_GROUP}' (${GID})"
info "     may assume permission set '${NB_PERMSET_NAME}'"
info "     in account ${TARGET_ACCOUNT}"

# ---- has this assignment already been made? ------------------------------
EXISTING="$(aws sso-admin list-account-assignments \
  --instance-arn "${INSTANCE_ARN}" \
  --account-id "${TARGET_ACCOUNT}" \
  --permission-set-arn "${PS_ARN}" \
  --query "AccountAssignments[?PrincipalId=='${GID}' && PrincipalType=='GROUP'].PrincipalId" \
  --output text 2>/dev/null || true)"

if [[ -n "${EXISTING}" && "${EXISTING}" != "None" ]]; then
  warn "Assignment already exists (skipping)."
else
  # create-account-assignment is asynchronous; it returns a request status.
  REQ_STATUS="$(run aws sso-admin create-account-assignment \
    --instance-arn "${INSTANCE_ARN}" \
    --target-id "${TARGET_ACCOUNT}" \
    --target-type AWS_ACCOUNT \
    --permission-set-arn "${PS_ARN}" \
    --principal-type GROUP \
    --principal-id "${GID}" \
    --query 'AccountAssignmentCreationStatus.Status' --output text)"
  info "Assignment submitted (status: ${REQ_STATUS}). Provisioning is async and usually completes in seconds."
fi

info "Done. The group can now assume '${NB_PERMSET_NAME}' in ${TARGET_ACCOUNT}."
info "Next: ./04-setup-profile.sh"
