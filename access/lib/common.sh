#!/usr/bin/env bash
# access/lib/common.sh
# Shared helpers for the NorthBank SSO setup scripts (01-05).
# Sourced, not executed:  source "$(dirname "$0")/lib/common.sh"
#
# Provides:
#   - config defaults (overridable via environment)
#   - logging helpers: info / warn / die / run
#   - lookups: current account id, SSO instance ARN, identity store id
#   - a require() guard for missing dependencies
#
# Everything here is intentionally verbose and commented: these scripts double
# as teaching material for Part B.

set -euo pipefail

# --------------------------------------------------------------------------
# Configuration (environment overrides win; see access/00-bootstrap-NOTES.md)
# --------------------------------------------------------------------------
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="${AWS_REGION}"   # keep the CLI's two region vars in sync

NB_PERMSET_NAME="${NB_PERMSET_NAME:-NorthBankPowerUser}"
NB_PERMSET_POLICY="${NB_PERMSET_POLICY:-arn:aws:iam::aws:policy/PowerUserAccess}"
NB_PERMSET_SESSION_DURATION="${NB_PERMSET_SESSION_DURATION:-PT4H}"   # ISO-8601; 4h session

NB_GROUP="${NB_GROUP:-NorthBank-Platform}"
NB_USER="${NB_USER:-northbank.newjoiner}"
NB_USER_EMAIL="${NB_USER_EMAIL:-newjoiner@example.com}"
NB_USER_GIVEN="${NB_USER_GIVEN:-New}"
NB_USER_FAMILY="${NB_USER_FAMILY:-Joiner}"

NB_PROFILE="${NB_PROFILE:-northbank}"

# --------------------------------------------------------------------------
# Logging helpers
# --------------------------------------------------------------------------
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# run: echo the exact command (so students see it on camera), then execute it.
run() {
  printf '\033[1;32m$ %s\033[0m\n' "$*" >&2
  "$@"
}

# require: fail early with a helpful message if a dependency is missing.
require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found on PATH. $2"
}

# --------------------------------------------------------------------------
# Dependency checks common to every script
# --------------------------------------------------------------------------
require aws "Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
# jq is optional; scripts degrade to --query when it's absent.
HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; fi

# --------------------------------------------------------------------------
# Lookups (memoized in globals so repeated calls don't re-hit the API)
# --------------------------------------------------------------------------

# current_account_id: the account the CLI is currently authenticated to.
current_account_id() {
  if [[ -z "${_NB_ACCOUNT_ID:-}" ]]; then
    _NB_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" \
      || die "Could not call sts:GetCallerIdentity — are you authenticated to the management account?"
  fi
  printf '%s' "$_NB_ACCOUNT_ID"
}

# sso_instance_arn: the IAM Identity Center instance ARN (created by the console bootstrap).
sso_instance_arn() {
  if [[ -z "${_NB_SSO_INSTANCE_ARN:-}" ]]; then
    _NB_SSO_INSTANCE_ARN="$(aws sso-admin list-instances \
      --query 'Instances[0].InstanceArn' --output text 2>/dev/null || true)"
    if [[ -z "$_NB_SSO_INSTANCE_ARN" || "$_NB_SSO_INSTANCE_ARN" == "None" ]]; then
      die "No IAM Identity Center instance found in region ${AWS_REGION}. Complete 00-bootstrap-NOTES.md first (enable Identity Center in this Region)."
    fi
  fi
  printf '%s' "$_NB_SSO_INSTANCE_ARN"
}

# identity_store_id: the Identity Store attached to the Identity Center instance.
identity_store_id() {
  if [[ -z "${_NB_IDENTITY_STORE_ID:-}" ]]; then
    _NB_IDENTITY_STORE_ID="$(aws sso-admin list-instances \
      --query 'Instances[0].IdentityStoreId' --output text 2>/dev/null || true)"
    [[ -n "$_NB_IDENTITY_STORE_ID" && "$_NB_IDENTITY_STORE_ID" != "None" ]] \
      || die "Could not resolve the Identity Store id. Is Identity Center enabled?"
  fi
  printf '%s' "$_NB_IDENTITY_STORE_ID"
}

# sso_start_url: the portal start URL for this Identity Center instance.
# (Not exposed by list-instances; derived from the account's SSO app portal.)
sso_start_url() {
  if [[ -z "${_NB_START_URL:-}" ]]; then
    # The start URL is https://<identity-store-id>.awsapps.com/start for the default portal,
    # unless a custom subdomain was set. We prefer an explicit override if provided.
    if [[ -n "${NB_START_URL:-}" ]]; then
      _NB_START_URL="$NB_START_URL"
    else
      _NB_START_URL="https://$(identity_store_id | sed 's/^.*\///').awsapps.com/start"
    fi
  fi
  printf '%s' "$_NB_START_URL"
}

# permission_set_arn: resolve a permission set ARN by its friendly name (or empty if absent).
permission_set_arn() {
  local name="$1" inst arn ps
  inst="$(sso_instance_arn)"
  for ps in $(aws sso-admin list-permission-sets --instance-arn "$inst" \
                --query 'PermissionSets[]' --output text); do
    arn="$(aws sso-admin describe-permission-set --instance-arn "$inst" \
             --permission-set-arn "$ps" --query 'PermissionSet.Name' --output text)"
    if [[ "$arn" == "$name" ]]; then printf '%s' "$ps"; return 0; fi
  done
  return 0   # not found -> empty output
}

# group_id / user_id: resolve Identity Store principals by name (empty if absent).
group_id() {
  aws identitystore list-groups --identity-store-id "$(identity_store_id)" \
    --filters "AttributePath=DisplayName,AttributeValue=$1" \
    --query 'Groups[0].GroupId' --output text 2>/dev/null | grep -v '^None$' || true
}
user_id() {
  aws identitystore list-users --identity-store-id "$(identity_store_id)" \
    --filters "AttributePath=UserName,AttributeValue=$1" \
    --query 'Users[0].UserId' --output text 2>/dev/null | grep -v '^None$' || true
}
