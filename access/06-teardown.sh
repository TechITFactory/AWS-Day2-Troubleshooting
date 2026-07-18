#!/usr/bin/env bash
# access/06-teardown.sh
#
# Undo everything 01-03 created, in reverse order, so you can run 01-03 again
# from a clean slate (e.g. before re-recording Part B).
#
# This does NOT touch AWS Organizations or the IAM Identity Center instance
# itself — those are the one-time console clicks in 00-bootstrap-NOTES.md.
# This only removes the account assignment, user, group, and permission set
# that this course's scripts created.
#
# Order matters: an account assignment must be deleted before the permission
# set it references can be deleted, and delete-account-assignment is async,
# so this script waits for it to finish before moving on.
#
# Idempotent: anything already gone is skipped, not treated as an error.
#
# Usage:
#   ./06-teardown.sh          # asks for confirmation first
#   ./06-teardown.sh --yes    # skips the confirmation

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CONFIRM=1
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
  CONFIRM=0
fi

INSTANCE_ARN="$(sso_instance_arn)"
STORE_ID="$(identity_store_id)"
TARGET_ACCOUNT="${NB_ACCOUNT_ID:-$(current_account_id)}"

info "About to remove everything created by 01-03 in account ${TARGET_ACCOUNT}:"
info "  - account assignment: group '${NB_GROUP}' -> permission set '${NB_PERMSET_NAME}' -> account ${TARGET_ACCOUNT}"
info "  - user '${NB_USER}' and group '${NB_GROUP}' (Identity Store)"
info "  - permission set '${NB_PERMSET_NAME}' (Identity Center)"
warn "This does NOT delete the Organization or the Identity Center instance itself — see 00-bootstrap-NOTES.md for that."

if [[ "${CONFIRM}" -eq 1 ]]; then
  read -r -p "Type 'yes' to continue: " ANSWER
  [[ "${ANSWER}" == "yes" ]] || die "Aborted."
fi

# ---- 1. remove the account assignment (reverse of 03) ----------------------
PS_ARN="$(permission_set_arn "${NB_PERMSET_NAME}")"
GID="$(group_id "${NB_GROUP}")"

if [[ -z "${PS_ARN}" || -z "${GID}" ]]; then
  warn "Permission set or group not found — assignment must already be gone (skipping)."
else
  EXISTING="$(aws sso-admin list-account-assignments \
    --instance-arn "${INSTANCE_ARN}" \
    --account-id "${TARGET_ACCOUNT}" \
    --permission-set-arn "${PS_ARN}" \
    --query "AccountAssignments[?PrincipalId=='${GID}' && PrincipalType=='GROUP'].PrincipalId" \
    --output text 2>/dev/null || true)"

  if [[ -z "${EXISTING}" || "${EXISTING}" == "None" ]]; then
    warn "No matching account assignment found (skipping)."
  else
    REQ_ID="$(run aws sso-admin delete-account-assignment \
      --instance-arn "${INSTANCE_ARN}" \
      --target-id "${TARGET_ACCOUNT}" \
      --target-type AWS_ACCOUNT \
      --permission-set-arn "${PS_ARN}" \
      --principal-type GROUP \
      --principal-id "${GID}" \
      --query 'AccountAssignmentDeletionStatus.RequestId' --output text)"
    info "Deletion submitted (request ${REQ_ID}), waiting for it to finish..."
    STATUS="IN_PROGRESS"
    while [[ "${STATUS}" == "IN_PROGRESS" ]]; do
      sleep 2
      STATUS="$(aws sso-admin describe-account-assignment-deletion-status \
        --instance-arn "${INSTANCE_ARN}" --account-assignment-deletion-request-id "${REQ_ID}" \
        --query 'AccountAssignmentDeletionStatus.Status' --output text)"
    done
    if [[ "${STATUS}" == "SUCCEEDED" ]]; then
      info "Assignment removed."
    else
      warn "Assignment deletion status: ${STATUS}"
    fi
  fi
fi

# ---- 2. remove group membership, user, group (reverse of 02) ---------------
UID_="$(user_id "${NB_USER}")"

if [[ -n "${GID}" && -n "${UID_}" ]]; then
  MEMBERSHIP_ID="$(aws identitystore list-group-memberships \
    --identity-store-id "${STORE_ID}" --group-id "${GID}" \
    --query "GroupMemberships[?MemberId.UserId=='${UID_}'].MembershipId" --output text 2>/dev/null || true)"
  if [[ -n "${MEMBERSHIP_ID}" && "${MEMBERSHIP_ID}" != "None" ]]; then
    run aws identitystore delete-group-membership \
      --identity-store-id "${STORE_ID}" --membership-id "${MEMBERSHIP_ID}"
    info "Removed '${NB_USER}' from '${NB_GROUP}'."
  fi
fi

if [[ -n "${UID_}" ]]; then
  run aws identitystore delete-user --identity-store-id "${STORE_ID}" --user-id "${UID_}"
  info "Deleted user '${NB_USER}'."
else
  warn "User '${NB_USER}' not found (skipping)."
fi

if [[ -n "${GID}" ]]; then
  run aws identitystore delete-group --identity-store-id "${STORE_ID}" --group-id "${GID}"
  info "Deleted group '${NB_GROUP}'."
else
  warn "Group '${NB_GROUP}' not found (skipping)."
fi

# ---- 3. detach the policy and delete the permission set (reverse of 01) ----
PS_ARN="$(permission_set_arn "${NB_PERMSET_NAME}")"
if [[ -z "${PS_ARN}" ]]; then
  warn "Permission set '${NB_PERMSET_NAME}' not found (skipping)."
else
  ATTACHED="$(aws sso-admin list-managed-policies-in-permission-set \
    --instance-arn "${INSTANCE_ARN}" --permission-set-arn "${PS_ARN}" \
    --query "AttachedManagedPolicies[?Arn=='${NB_PERMSET_POLICY}'].Arn" --output text)"
  if [[ -n "${ATTACHED}" ]]; then
    run aws sso-admin detach-managed-policy-from-permission-set \
      --instance-arn "${INSTANCE_ARN}" --permission-set-arn "${PS_ARN}" \
      --managed-policy-arn "${NB_PERMSET_POLICY}"
    info "Detached ${NB_PERMSET_POLICY}."
  fi
  run aws sso-admin delete-permission-set \
    --instance-arn "${INSTANCE_ARN}" --permission-set-arn "${PS_ARN}"
  info "Deleted permission set '${NB_PERMSET_NAME}'."
fi

echo
info "Done. Everything from 01-03 is removed."
info "~/.aws/config was left untouched (its northbank blocks are harmless if the account ID hasn't changed) —"
info "delete the [sso-session northbank] and [profile ${NB_PROFILE}] blocks yourself if you want those gone too."
info "Re-run ./01-create-permission-sets.sh to start fresh."
