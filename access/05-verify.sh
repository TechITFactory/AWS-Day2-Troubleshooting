#!/usr/bin/env bash
# access/05-verify.sh
#
# Prove who you are and which account you're pointing at — for every profile.
# This is the exact habit taught in Part B and reused as step 1 of Lab 1's
# triage flow: ALWAYS confirm identity + account before you run anything.
#
# Usage:
#   ./05-verify.sh                 # verify the default NB_PROFILE
#   ./05-verify.sh prod nonprod    # verify several named profiles

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Profiles to check: args if given, else the default one.
PROFILES=("$@")
if [[ ${#PROFILES[@]} -eq 0 ]]; then
  PROFILES=("${NB_PROFILE}")
fi

rc=0
for p in "${PROFILES[@]}"; do
  echo
  info "=== profile: ${p} ==="
  if OUT="$(aws sts get-caller-identity --profile "${p}" --output json 2>&1)"; then
    if [[ "${HAVE_JQ}" -eq 1 ]]; then
      acct="$(printf '%s' "${OUT}" | jq -r '.Account')"
      arn="$(printf '%s'  "${OUT}" | jq -r '.Arn')"
    else
      acct="$(printf '%s' "${OUT}" | aws --output text --query 'Account' 2>/dev/null || echo '?')"
      arn="$(printf '%s'  "${OUT}")"
    fi
    printf '  \033[1;32mAccount:\033[0m %s\n' "${acct}"
    printf '  \033[1;32mArn    :\033[0m %s\n' "${arn}"
  else
    # The teachable failure: session expired.
    if printf '%s' "${OUT}" | grep -qiE 'expired|sso|Token'; then
      warn "profile '${p}': session looks expired. This is NORMAL — just log in again:"
      warn "    aws sso login --profile ${p}"
    else
      warn "profile '${p}': ${OUT}"
    fi
    rc=1
  fi
done

echo
if [[ ${rc} -eq 0 ]]; then
  info "All profiles verified. You know who you are and where you are. That's the habit."
else
  warn "One or more profiles need a fresh 'aws sso login'. Not a bug — sessions expire by design."
fi
exit "${rc}"
