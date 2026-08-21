#!/usr/bin/env bash
# Proves the two guarantees the pilot's cost story depends on:
#   1. a virtual key's hard budget actually blocks requests once exhausted
#   2. a virtual key cannot reach a model outside its allowlist
# Creates and deletes its own throwaway keys. Requires the master key.
set -euo pipefail

PROXY_URL=${1:-"http://localhost:4000"}
MASTER_KEY=${2:-${LITELLM_MASTER_KEY:-}}
PROXY_URL=${PROXY_URL%/}

# Small enough that a single flagship call blows through it.
PROBE_BUDGET=${PROBE_BUDGET:-0.000001}
MAX_ATTEMPTS=${MAX_ATTEMPTS:-12}
SPEND_FLUSH_WAIT=${SPEND_FLUSH_WAIT:-4}

for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: '$bin' is required but not installed." >&2; exit 1; }
done

if [ -z "$MASTER_KEY" ]; then
  echo "Error: LITELLM_MASTER_KEY must be supplied (argument 2 or environment variable)." >&2
  exit 1
fi

BODY=$(mktemp)
CREATED_KEYS=()

cleanup() {
  for k in ${CREATED_KEYS+"${CREATED_KEYS[@]}"}; do
    curl -sS -o /dev/null -X POST "$PROXY_URL/key/delete" \
      -H "Authorization: Bearer $MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg k "$k" '{keys: [$k]}')" || true
    echo "Cleaned up throwaway key ${k:0:12}..."
  done
  rm -f "$BODY"
}
trap cleanup EXIT

fail() { echo "  -> FAIL: $*" >&2; exit 1; }

mint_key() {
  # $1 = alias suffix, $2 = max_budget, $3 = JSON array of allowed models
  local alias="ctrl-probe-$1-$$" budget=$2 models=$3
  local status
  status=$(jq -n --arg a "$alias" --argjson b "$budget" --argjson m "$models" \
      '{key_alias: $a, max_budget: $b, budget_duration: "30d", models: $m}' \
    | curl -sS -o "$BODY" -w "%{http_code}" -X POST "$PROXY_URL/key/generate" \
        -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" -d @-)
  if [ "$status" != "200" ]; then
    cat "$BODY" >&2; echo >&2
    fail "could not mint throwaway key (HTTP $status). /key/generate needs Postgres (DATABASE_URL)."
  fi
  jq -r '.key' <"$BODY"
}

chat() {
  # $1 = key, $2 = model, $3 = prompt -> echoes HTTP status, body in $BODY
  jq -n --arg model "$2" --arg content "$3" \
    '{model: $model, messages: [{role: "user", content: $content}], max_tokens: 8}' \
  | curl -sS --max-time 120 -o "$BODY" -w "%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
      -H "Authorization: Bearer $1" -H "Content-Type: application/json" -d @-
}

key_spend() {
  curl -sS -G "$PROXY_URL/key/info" --data-urlencode "key=$1" \
    -H "Authorization: Bearer $MASTER_KEY" | jq -r '.info.spend // 0'
}

# ============================================================ 1. cap persists
echo "[1/3] Verifying the \$30 cap is stored on generated keys..."
CAP_KEY=$(mint_key "cap" 30.0 '["tier-1-fast","tier-2-balanced","tier-3-flagship"]')
CREATED_KEYS+=("$CAP_KEY")
CAP_INFO=$(curl -sS -G "$PROXY_URL/key/info" --data-urlencode "key=$CAP_KEY" \
  -H "Authorization: Bearer $MASTER_KEY")
STORED_BUDGET=$(echo "$CAP_INFO" | jq -r '.info.max_budget // "null"')
STORED_DURATION=$(echo "$CAP_INFO" | jq -r '.info.budget_duration // "null"')
[ "$STORED_BUDGET" = "30" ] || [ "$STORED_BUDGET" = "30.0" ] \
  || fail "expected max_budget 30, proxy stored '$STORED_BUDGET'"
echo "  -> PASS: max_budget=$STORED_BUDGET, budget_duration=$STORED_DURATION"

# ====================================================== 2. budget enforcement
echo "[2/3] Verifying budget exhaustion blocks requests (cap: \$$PROBE_BUDGET)..."
BUDGET_KEY=$(mint_key "budget" "$PROBE_BUDGET" '["tier-3-flagship"]')
CREATED_KEYS+=("$BUDGET_KEY")

BLOCKED=0
for i in $(seq 1 "$MAX_ATTEMPTS"); do
  # Unique prompt each time; a cache hit would cost nothing and never trip the cap.
  STATUS=$(chat "$BUDGET_KEY" "tier-3-flagship" "Budget probe $i [$RANDOM-$(date +%s)]: say OK")

  if [ "$STATUS" = "200" ]; then
    echo "  -> attempt $i: 200 OK (spend so far: \$$(key_spend "$BUDGET_KEY"))"
    sleep "$SPEND_FLUSH_WAIT"
    continue
  fi

  ERR_TYPE=$(jq -r '.error.type // ""' <"$BODY")
  ERR_MSG=$(jq -r '.error.message // .detail.error // .detail // ""' <"$BODY" | tr -d '\n')
  echo "  -> attempt $i: HTTP $STATUS ($ERR_TYPE)"
  echo "     $ERR_MSG"

  case "$ERR_TYPE$ERR_MSG" in
    *budget_exceeded*|*ExceededBudget*|*"Budget has been exceeded"*|*"Max budget limit reached"*)
      BLOCKED=1; break ;;
    *)
      fail "request was rejected, but not for budget reasons (HTTP $STATUS)" ;;
  esac
done

[ "$BLOCKED" -eq 1 ] || fail "key still served requests after $MAX_ATTEMPTS calls over its \$$PROBE_BUDGET cap.
       Cost tracking may not be resolving prices for this model - check /spend/logs."

FINAL_SPEND=$(key_spend "$BUDGET_KEY")
echo "  -> PASS: blocked after exceeding cap (recorded spend: \$$FINAL_SPEND)"
[ "$FINAL_SPEND" != "0" ] || echo "     WARNING: recorded spend is 0; budgets rely on this counter." >&2

# ========================================================= 3. model allowlist
echo "[3/3] Verifying model allowlist scoping..."
SCOPED_KEY=$(mint_key "scope" 30.0 '["tier-1-fast"]')
CREATED_KEYS+=("$SCOPED_KEY")

STATUS=$(chat "$SCOPED_KEY" "tier-1-fast" "Allowed model probe [$RANDOM]: say OK")
[ "$STATUS" = "200" ] || { cat "$BODY" >&2; fail "allowed model tier-1-fast was rejected (HTTP $STATUS)"; }
echo "  -> allowed model tier-1-fast: 200 OK"

STATUS=$(chat "$SCOPED_KEY" "tier-3-flagship" "Denied model probe [$RANDOM]: say OK")
if [ "$STATUS" = "200" ]; then
  fail "key scoped to tier-1-fast was still served by tier-3-flagship"
fi
DENY_MSG=$(jq -r '.error.message // .detail.error // .detail // ""' <"$BODY" | tr -d '\n')
echo "  -> denied model tier-3-flagship: HTTP $STATUS"
echo "     $DENY_MSG"
echo "  -> PASS: allowlist enforced"

echo
echo "All key control tests passed!"
