#!/usr/bin/env bash
# labs/00-prerequisites/set-budget.sh
#
# Creates a monthly AWS Budget with an email alert, so if you forget to tear a
# lab down you get an email instead of a surprise bill. Run this ONCE, before
# you start (Prerequisites Step 1 / the recording runbook).
#
# Idempotent: if the budget already exists, it's left alone.
#
# Usage:
#   ./set-budget.sh                        # prompts for email + amount
#   NB_BUDGET_EMAIL=you@example.com ./set-budget.sh
#   NB_BUDGET_EMAIL=you@example.com NB_BUDGET_AMOUNT=15 NB_BUDGET_THRESHOLD=80 ./set-budget.sh
#
# Env vars (all optional — email and amount are prompted for if unset):
#   NB_BUDGET_EMAIL      prompted, default: demo@example.com   address to notify
#   NB_BUDGET_NAME       default: aws-day2
#   NB_BUDGET_AMOUNT     prompted, default: 10                 (USD / month)
#   NB_BUDGET_THRESHOLD  default: 80      (% of budget that triggers the alert)
set -euo pipefail

NAME="${NB_BUDGET_NAME:-aws-day2}"
THRESHOLD="${NB_BUDGET_THRESHOLD:-80}"

if [[ -z "${NB_BUDGET_EMAIL:-}" ]]; then
  read -rp "Email to notify [demo@example.com]: " NB_BUDGET_EMAIL
fi
EMAIL="${NB_BUDGET_EMAIL:-demo@example.com}"

if [[ -z "${NB_BUDGET_AMOUNT:-}" ]]; then
  read -rp "Monthly budget in USD [10]: " NB_BUDGET_AMOUNT
fi
AMOUNT="${NB_BUDGET_AMOUNT:-10}"

# Budgets is a global service; the API lives in us-east-1 regardless of AWS_REGION.
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

echo "[budget] Account:   ${ACCOUNT_ID}"
echo "[budget] Budget:    ${NAME} = \$${AMOUNT}/month, alert at ${THRESHOLD}%"
echo "[budget] Notify:    ${EMAIL}"

# Already exists? Then don't recreate it.
if aws budgets describe-budget --account-id "${ACCOUNT_ID}" --budget-name "${NAME}" \
     --region us-east-1 >/dev/null 2>&1; then
  echo "[budget] Budget '${NAME}' already exists — leaving it as-is."
  exit 0
fi

aws budgets create-budget \
  --region us-east-1 \
  --account-id "${ACCOUNT_ID}" \
  --budget "{
    \"BudgetName\": \"${NAME}\",
    \"BudgetLimit\": { \"Amount\": \"${AMOUNT}\", \"Unit\": \"USD\" },
    \"TimeUnit\": \"MONTHLY\",
    \"BudgetType\": \"COST\"
  }" \
  --notifications-with-subscribers "[
    {
      \"Notification\": {
        \"NotificationType\": \"ACTUAL\",
        \"ComparisonOperator\": \"GREATER_THAN\",
        \"Threshold\": ${THRESHOLD},
        \"ThresholdType\": \"PERCENTAGE\"
      },
      \"Subscribers\": [
        { \"SubscriptionType\": \"EMAIL\", \"Address\": \"${EMAIL}\" }
      ]
    }
  ]"

echo "[budget] Done. '${NAME}' created — you'll get an email at ${THRESHOLD}% of \$${AMOUNT}."
