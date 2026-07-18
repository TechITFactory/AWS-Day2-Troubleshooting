#!/usr/bin/env bash
# access/02-create-users-groups.sh
#
# Create a group and a user in the IAM Identity Center *Identity Store*, then
# put the user in the group. In the real world you assign access to GROUPS
# (not individuals) so joiners/movers/leavers is just group membership.
#
# Idempotent: existing group/user/membership are detected and skipped.
#
# Run from the management account (admin).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

STORE_ID="$(identity_store_id)"
info "Identity Store: ${STORE_ID}"

# ---- group ----------------------------------------------------------------
GID="$(group_id "${NB_GROUP}")"
if [[ -n "${GID}" ]]; then
  warn "Group '${NB_GROUP}' already exists: ${GID} (skipping create)"
else
  GID="$(run aws identitystore create-group \
    --identity-store-id "${STORE_ID}" \
    --display-name "${NB_GROUP}" \
    --description "NorthBank Platform team" \
    --query 'GroupId' --output text)"
  info "Created group '${NB_GROUP}': ${GID}"
fi

# ---- user -----------------------------------------------------------------
UID_="$(user_id "${NB_USER}")"
if [[ -n "${UID_}" ]]; then
  warn "User '${NB_USER}' already exists: ${UID_} (skipping create)"
else
  UID_="$(run aws identitystore create-user \
    --identity-store-id "${STORE_ID}" \
    --user-name "${NB_USER}" \
    --display-name "${NB_USER_GIVEN} ${NB_USER_FAMILY}" \
    --name "GivenName=${NB_USER_GIVEN},FamilyName=${NB_USER_FAMILY}" \
    --emails "Value=${NB_USER_EMAIL},Type=work,Primary=true" \
    --query 'UserId' --output text)"
  info "Created user '${NB_USER}': ${UID_}"
  warn "The user must set a password via the invitation email / Identity Center console before they can sign in."
fi

# ---- membership -----------------------------------------------------------
EXISTING_MEMBERSHIP="$(aws identitystore list-group-memberships \
  --identity-store-id "${STORE_ID}" --group-id "${GID}" \
  --query "GroupMemberships[?MemberId.UserId=='${UID_}'].MembershipId" --output text)"

if [[ -n "${EXISTING_MEMBERSHIP}" && "${EXISTING_MEMBERSHIP}" != "None" ]]; then
  warn "User is already a member of '${NB_GROUP}' (skipping)"
else
  run aws identitystore create-group-membership \
    --identity-store-id "${STORE_ID}" \
    --group-id "${GID}" \
    --member-id "UserId=${UID_}" >/dev/null
  info "Added '${NB_USER}' to '${NB_GROUP}'"
fi

info "Done. Group ${GID} / User ${UID_}"
info "Next: ./03-assign-access.sh"
