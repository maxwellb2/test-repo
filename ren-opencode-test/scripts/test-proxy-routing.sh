#!/usr/bin/env bash
# Verifies the request paths a developer's IDE actually uses: tier routing,
# prompt caching, and streaming. Runs with a developer virtual key.
set -euo pipefail

PROXY_URL=${1:-"http://localhost:4000"}
API_KEY=${2:-"sk-test-key"}
PROXY_URL=${PROXY_URL%/}

TIERS=("tier-1-fast" "tier-2-balanced" "tier-3-flagship")
NONCE="$(date +%s)-${RANDOM}"

for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: '$bin' is required but not installed." >&2; exit 1; }
done

BODY=$(mktemp)
STREAM=$(mktemp)
trap 'rm -f "$BODY" "$STREAM"' EXIT

call_tier() {
  local tier=$1 prompt=$2
  jq -n --arg model "$tier" --arg content "$prompt" \
    '{model: $model, messages: [{role: "user", content: $content}], max_tokens: 5, temperature: 0}' \
  | curl -sS --max-time 120 -o "$BODY" -w "%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d @-
}

call_tier_stream() {
  local tier=$1 prompt=$2
  jq -n --arg model "$tier" --arg content "$prompt" \
    '{model: $model, messages: [{role: "user", content: $content}], max_tokens: 32, stream: true}' \
  | curl -sS -N --max-time 120 -o "$STREAM" -w "%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d @-
}

fail() { echo "  -> FAIL: $*" >&2; exit 1; }

# ---------------------------------------------------------------- liveliness
echo "Checking proxy liveliness at $PROXY_URL ..."
LIVE=$(curl -sS --max-time 15 -o /dev/null -w "%{http_code}" "$PROXY_URL/health/liveliness")
[ "$LIVE" = "200" ] || fail "proxy not live (HTTP $LIVE)"
echo "  -> Proxy is live."

# --------------------------------------------------------------- tier routing
for TIER in "${TIERS[@]}"; do
  echo "Testing endpoint tier: $TIER..."
  STATUS=$(call_tier "$TIER" "Respond with string OK. [$NONCE]")

  if [ "$STATUS" != "200" ]; then
    cat "$BODY" >&2; echo >&2
    fail "Received HTTP Status $STATUS"
  fi

  SERVED=$(jq -r '.model // "unknown"' <"$BODY")
  TOKENS=$(jq -r '.usage.total_tokens // "n/a"' <"$BODY")
  echo "  -> Status: 200 OK (served by: $SERVED, tokens: $TOKENS)"
done

# ------------------------------------------------------------- prompt caching
# The nonce guarantees the first call is a genuine miss, so re-running the
# suite cannot make this assertion pass trivially. LiteLLM signals a cache hit
# by replaying the original response id.
echo "Testing prompt cache on tier-2-balanced..."
CACHE_PROMPT="Cache probe [$NONCE]: respond with string OK"

STATUS=$(call_tier "tier-2-balanced" "$CACHE_PROMPT")
[ "$STATUS" = "200" ] || { cat "$BODY" >&2; fail "cache probe request failed (HTTP $STATUS)"; }
FIRST_ID=$(jq -r '.id // empty' <"$BODY")

sleep 1
STATUS=$(call_tier "tier-2-balanced" "$CACHE_PROMPT")
[ "$STATUS" = "200" ] || { cat "$BODY" >&2; fail "cache probe repeat failed (HTTP $STATUS)"; }
SECOND_ID=$(jq -r '.id // empty' <"$BODY")

if [ -n "$FIRST_ID" ] && [ "$FIRST_ID" = "$SECOND_ID" ]; then
  echo "  -> Cache HIT (response id replayed: $FIRST_ID)"
else
  fail "cache MISS (ids: '$FIRST_ID' vs '$SECOND_ID') - check litellm_settings.cache in litellm-config.yaml"
fi

# ------------------------------------------------------------------ streaming
# Continue.dev streams every request, so the SSE path matters more than the
# buffered one tested above.
echo "Testing streaming on tier-1-fast..."
STATUS=$(call_tier_stream "tier-1-fast" "Count from 1 to 5. [$NONCE]")
[ "$STATUS" = "200" ] || { cat "$STREAM" >&2; fail "streaming request failed (HTTP $STATUS)"; }

CHUNKS=$(grep -c '^data: ' "$STREAM" || true)
DONE=$(grep -c '^data: \[DONE\]' "$STREAM" || true)
CONTENT=$(grep '^data: ' "$STREAM" | grep -v '^data: \[DONE\]' | cut -c7- \
  | jq -rs 'map(.choices[0].delta.content // "") | join("")' 2>/dev/null || echo "")

[ "$CHUNKS" -ge 2 ] || fail "expected multiple SSE chunks, got $CHUNKS (is the proxy buffering?)"
[ "$DONE" -ge 1 ] || fail "stream never terminated with [DONE]"
[ -n "$CONTENT" ] || fail "stream carried no delta content"
echo "  -> Streamed $CHUNKS chunks, terminated correctly (text: $(echo "$CONTENT" | tr '\n' ' ' | cut -c1-40))"

echo
echo "All routing, caching, and streaming tests passed!"
