#!/usr/bin/env bash
set -euo pipefail

PROXY_URL=${1:-"http://localhost:4000"}
MASTER_KEY=${2:-${LITELLM_MASTER_KEY:-}}
DEV_ALIAS=${3:-"pilot-dev-1"}
MAX_BUDGET=${MAX_BUDGET:-30.0}
BUDGET_DURATION=${BUDGET_DURATION:-30d}

PROXY_URL=${PROXY_URL%/}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATE="$REPO_ROOT/client/.continue/config.json"
OUT_DIR="$REPO_ROOT/client/.continue/generated/$DEV_ALIAS"

for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: '$bin' is required but not installed." >&2; exit 1; }
done

if [ -z "$MASTER_KEY" ]; then
  echo "Error: LITELLM_MASTER_KEY must be supplied (argument 2 or environment variable)." >&2
  exit 1
fi

echo "Generating virtual key for: $DEV_ALIAS with \$$MAX_BUDGET / $BUDGET_DURATION budget..."

REQUEST=$(jq -n \
  --arg user_id "$DEV_ALIAS" \
  --arg key_alias "$DEV_ALIAS-key" \
  --arg budget_duration "$BUDGET_DURATION" \
  --argjson max_budget "$MAX_BUDGET" \
  '{
     user_id: $user_id,
     key_alias: $key_alias,
     max_budget: $max_budget,
     budget_duration: $budget_duration,
     models: ["tier-1-fast", "tier-2-balanced", "tier-3-flagship"],
     metadata: { pilot: "enterprise-ai-coding-stack" }
   }')

HTTP_BODY=$(mktemp)
trap 'rm -f "$HTTP_BODY"' EXIT

STATUS=$(curl -sS -o "$HTTP_BODY" -w "%{http_code}" -X POST "$PROXY_URL/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "$REQUEST")

if [ "$STATUS" != "200" ]; then
  echo "Error: key generation failed with HTTP $STATUS" >&2
  cat "$HTTP_BODY" >&2
  echo >&2
  case "$STATUS" in
    401|403) echo "Hint: LITELLM_MASTER_KEY does not match the proxy's master key." >&2 ;;
    *) echo "Hint: /key/generate requires the proxy to be connected to Postgres (DATABASE_URL)." >&2 ;;
  esac
  exit 1
fi

KEY=$(jq -r '.key // empty' <"$HTTP_BODY")
if [ -z "$KEY" ]; then
  echo "Error: proxy returned no key." >&2
  cat "$HTTP_BODY" >&2
  exit 1
fi

# Render a ready-to-use Continue config: config.json has no variable expansion,
# so the proxy URL and virtual key are baked in per developer.
mkdir -p "$OUT_DIR"
jq \
  --arg base "$PROXY_URL/v1" \
  --arg key "$KEY" \
  '(.. | objects | select(has("apiBase")).apiBase) = $base
   | (.. | objects | select(has("apiKey")).apiKey) = $key' \
  "$TEMPLATE" >"$OUT_DIR/config.json"

echo "----------------------------------------"
echo "Developer Key Created Successfully!"
echo "Developer Alias : $DEV_ALIAS"
echo "API Key         : $KEY"
echo "Monthly Limit   : \$$MAX_BUDGET USD / $BUDGET_DURATION"
echo "Continue config : $OUT_DIR/config.json"
echo "----------------------------------------"
echo "Ship to the developer with:"
echo "  cp \"$OUT_DIR/config.json\" ~/.continue/config.json"
