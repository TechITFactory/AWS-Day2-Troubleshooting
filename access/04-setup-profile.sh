#!/usr/bin/env bash
# access/04-setup-profile.sh
#
# Write the ~/.aws/config blocks BY HAND (well, by script — but showing exactly
# what goes in the file), then run `aws sso login`. This is the CLI login flow
# new hires struggle with; seeing the file demystifies it.
#
# Writes:
#   [sso-session northbank]  — the shared login (start URL + region)
#   [profile northbank]      — account + role to reach
#
# Idempotent: if the [profile <name>] block already exists we leave the file
# alone and just log in. We never blindly clobber ~/.aws/config.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

TARGET_ACCOUNT="${NB_ACCOUNT_ID:-$(current_account_id)}"
START_URL="$(sso_start_url)"
SESSION_NAME="northbank"
CONFIG_FILE="${AWS_CONFIG_FILE:-${HOME}/.aws/config}"

info "Profile name : ${NB_PROFILE}"
info "Start URL    : ${START_URL}"
info "Account      : ${TARGET_ACCOUNT}"
info "Role         : ${NB_PERMSET_NAME}"
info "Config file  : ${CONFIG_FILE}"

mkdir -p "$(dirname "${CONFIG_FILE}")"
touch "${CONFIG_FILE}"

# ---- sso-session block ----------------------------------------------------
if grep -q "^\[sso-session ${SESSION_NAME}\]" "${CONFIG_FILE}"; then
  warn "[sso-session ${SESSION_NAME}] already present — leaving it as-is."
else
  info "Appending [sso-session ${SESSION_NAME}] block."
  cat >> "${CONFIG_FILE}" <<EOF

[sso-session ${SESSION_NAME}]
sso_start_url = ${START_URL}
sso_region = ${AWS_REGION}
sso_registration_scopes = sso:account:access
EOF
fi

# ---- profile block --------------------------------------------------------
if grep -q "^\[profile ${NB_PROFILE}\]" "${CONFIG_FILE}"; then
  warn "[profile ${NB_PROFILE}] already present — leaving it as-is."
else
  info "Appending [profile ${NB_PROFILE}] block."
  cat >> "${CONFIG_FILE}" <<EOF

[profile ${NB_PROFILE}]
sso_session = ${SESSION_NAME}
sso_account_id = ${TARGET_ACCOUNT}
sso_role_name = ${NB_PERMSET_NAME}
region = ${AWS_REGION}
output = json
EOF
fi

echo
info "Here is the config that will be used (grep of ${CONFIG_FILE}):"
grep -A4 -e "^\[sso-session ${SESSION_NAME}\]" -e "^\[profile ${NB_PROFILE}\]" "${CONFIG_FILE}" || true
echo

# ---- log in ---------------------------------------------------------------
info "Opening browser for device authorization (human-in-the-loop by design)…"
run aws sso login --sso-session "${SESSION_NAME}"

info "Done. Logged in via SSO session '${SESSION_NAME}'."
info "Next: ./05-verify.sh"
