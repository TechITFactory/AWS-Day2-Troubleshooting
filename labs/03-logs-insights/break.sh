#!/usr/bin/env bash
# labs/03-logs-insights/break.sh
#
# FAULT SIMULATED: seeds a CloudWatch Logs group (/northbank/app) with a
# realistic mix of log lines. ~90% are normal 200s; a slice are 500 errors on
# the /transfer endpoint, all caused by "DBConnectionTimeout". The learner uses
# Logs Insights to find that pattern.
#
# WHY SEED LOGS: in production the CloudWatch agent ships these app logs for us.
# In the lab we write them directly with put-log-events so the lesson (querying)
# works without wiring the agent. The SOLUTION explains the real-world path.
#
# INTENDED DIAGNOSIS PATH:
#   Logs Insights -> stats count() by status  ->  see 500s  ->  filter status=500
#   ->  stats count() by endpoint  ->  /transfer  ->  read the error field  ->
#   "DBConnectionTimeout". Then add a metric filter + alarm.
#
# REVERSIBLE: yes. Deletes/recreates only the /northbank/app log group.
# Sandbox only.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
LOG_GROUP="/northbank/app"
LOG_STREAM="web-$(printf '%04d' "$(( ${RANDOM:-1} % 10000 ))")"   # varied per run
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.break-state.json"

echo "[break] Region: ${REGION}"
echo "[break] Seeding log group ${LOG_GROUP} (stream ${LOG_STREAM})"

# (Re)create the log group + stream.
aws logs create-log-group  --region "${REGION}" --log-group-name "${LOG_GROUP}" 2>/dev/null || true
aws logs create-log-stream --region "${REGION}" --log-group-name "${LOG_GROUP}" --log-stream-name "${LOG_STREAM}" 2>/dev/null || true

# Build a batch of JSON log events. Timestamps must be epoch-millis and within
# the last 14 days. We spread them over the last ~20 minutes.
NOW_MS=$(( $(date +%s) * 1000 ))
EVENTS_FILE="$(mktemp)"
printf '[' > "${EVENTS_FILE}"

emit() { # $1 = offset ms back, $2 = message
  local ts=$(( NOW_MS - $1 ))
  printf '%s{"timestamp":%d,"message":%s}' "${SEP:-}" "${ts}" "$(printf '%s' "$2" | jq -Rsc .)" >> "${EVENTS_FILE}"
  SEP=','
}

# jq is used to safely JSON-encode messages. Fall back with a clear error if absent.
command -v jq >/dev/null 2>&1 || { echo "[break] ERROR: this lab's seeder needs 'jq'." >&2; exit 1; }

i=0
while [ $i -lt 60 ]; do
  off=$(( (60 - i) * 20000 ))   # spread over ~20 min
  if [ $(( i % 7 )) -eq 0 ]; then
    # the failing pattern: 500 on /transfer due to a DB timeout
    emit "$off" '{"level":"ERROR","status":500,"endpoint":"/transfer","latency_ms":30021,"error":"DBConnectionTimeout: could not get connection from pool within 30000ms","request_id":"req-'"$i"'"}'
  else
    ep=$( [ $(( i % 2 )) -eq 0 ] && echo "/balance" || echo "/login" )
    emit "$off" '{"level":"INFO","status":200,"endpoint":"'"$ep"'","latency_ms":'"$(( 20 + i ))"',"request_id":"req-'"$i"'"}'
  fi
  i=$(( i + 1 ))
done
printf ']' >> "${EVENTS_FILE}"

# On native Linux/Mac this path is fine as-is. On Windows Git Bash, the AWS
# CLI is a native Windows exe and can't resolve a Git-Bash-style /tmp path
# inside a file:// URI, so convert it if cygpath is present.
if command -v cygpath >/dev/null 2>&1; then
  EVENTS_FILE_URI="file://$(cygpath -w "${EVENTS_FILE}")"
else
  EVENTS_FILE_URI="file://${EVENTS_FILE}"
fi

aws logs put-log-events \
  --region "${REGION}" \
  --log-group-name "${LOG_GROUP}" \
  --log-stream-name "${LOG_STREAM}" \
  --log-events "${EVENTS_FILE_URI}" >/dev/null
rm -f "${EVENTS_FILE}"

cat > "${STATE_FILE}" <<JSON
{
  "lab": "03-logs-insights",
  "region": "${REGION}",
  "log_group": "${LOG_GROUP}",
  "log_stream": "${LOG_STREAM}",
  "planted_pattern": "500 on /transfer with error=DBConnectionTimeout (~1 in 7 requests)"
}
JSON

cat <<'MSG'

────────────────────────────────────────────────────────────
  NB-0301  SEV-2  — reported by Marco (App team)
  "Some banking transfers fail intermittently. Logs only."
────────────────────────────────────────────────────────────
  Start in CloudWatch Logs Insights on log group:
      /northbank/app
  Find which endpoint fails and the common error behind it.
────────────────────────────────────────────────────────────
MSG

echo "[break] Done. Planted pattern recorded in ${STATE_FILE}" >&2
