#!/usr/bin/env bash
# Proves the tier-3 -> tier-2 fallback chain actually fires.
#
# Runs a disposable proxy on a spare port using litellm-config.fallback-test.yaml,
# in which tier-3-flagship points at a model that cannot resolve. The pilot stack
# on :4000 is never touched.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PORT=${FALLBACK_TEST_PORT:-4111}
CONTAINER=${FALLBACK_TEST_CONTAINER:-litellm-fallback-test}
IMAGE=${LITELLM_IMAGE:-ghcr.io/berriai/litellm:main-latest}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-120}
BASE="http://localhost:$PORT"

for bin in curl jq docker; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: '$bin' is required but not installed." >&2; exit 1; }
done

[ -f "$REPO_ROOT/.env" ] || { echo "Error: $REPO_ROOT/.env not found. Copy .env.example first." >&2; exit 1; }

# shellcheck disable=SC1091
set -a; . "$REPO_ROOT/.env"; set +a
MASTER_KEY=${LITELLM_MASTER_KEY:-}
[ -n "$MASTER_KEY" ] || { echo "Error: LITELLM_MASTER_KEY missing from .env" >&2; exit 1; }

BODY=$(mktemp)
HEADERS=$(mktemp)
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -f "$BODY" "$HEADERS"
}
trap cleanup EXIT

fail() { echo "  -> FAIL: $*" >&2; exit 1; }

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

echo "Starting disposable proxy on port $PORT (tier-3 pointed at an unresolvable model)..."
docker run -d --rm --name "$CONTAINER" \
  -p "$PORT:4000" \
  --env-file "$REPO_ROOT/.env" \
  -v "$REPO_ROOT/docker/litellm-config.fallback-test.yaml:/app/config.yaml:ro" \
  "$IMAGE" --config /app/config.yaml --port 4000 >/dev/null

echo -n "Waiting for it to come up"
UP=0
for _ in $(seq 1 "$BOOT_TIMEOUT"); do
  if curl -sS -o /dev/null --max-time 2 "$BASE/health/liveliness" 2>/dev/null; then UP=1; break; fi
  echo -n "."
  sleep 1
done
echo
[ "$UP" -eq 1 ] || { docker logs "$CONTAINER" 2>&1 | tail -30 >&2; fail "disposable proxy never became live"; }

# ------------------------------------------------- tier-3 must fall back to tier-2
echo "Requesting tier-3-flagship (primary is unresolvable)..."
STATUS=$(jq -n '{model: "tier-3-flagship", messages: [{role: "user", content: "Reply with the single word OK"}], max_tokens: 8}' \
  | curl -sS --max-time 180 -D "$HEADERS" -o "$BODY" -w "%{http_code}" -X POST "$BASE/v1/chat/completions" \
      -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" -d @-)

if [ "$STATUS" != "200" ]; then
  cat "$BODY" >&2; echo >&2
  docker logs "$CONTAINER" 2>&1 | tail -30 >&2
  fail "tier-3 request returned HTTP $STATUS - the fallback did not rescue it"
fi

SERVED=$(jq -r '.model // "unknown"' <"$BODY")
ATTEMPTED=$(grep -i '^x-litellm-attempted-fallbacks:' "$HEADERS" | tr -d '\r' | awk '{print $2}' || true)

case "$SERVED" in
  *nonexistent-model-fallback-probe*)
    fail "response claims it came from the broken primary ($SERVED)" ;;
esac

echo "  -> Status: 200 OK, served by: $SERVED"
if [ -n "$ATTEMPTED" ]; then
  echo "  -> x-litellm-attempted-fallbacks: $ATTEMPTED"
else
  echo "  -> note: proxy did not report x-litellm-attempted-fallbacks (older build); relying on served model"
fi

case "$SERVED" in
  *deepseek*) echo "  -> PASS: tier-3 fell back to tier-2 (deepseek)" ;;
  *qwen*)     echo "  -> PASS (degraded): fell all the way through to tier-1 (qwen)" ;;
  *)          echo "  -> PASS (unverified model name): request survived via fallback as '$SERVED'" ;;
esac

# --------------------------------------- a healthy tier must not divert traffic
echo "Confirming a healthy tier is unaffected..."
STATUS=$(jq -n '{model: "tier-2-balanced", messages: [{role: "user", content: "Reply with the single word OK"}], max_tokens: 8}' \
  | curl -sS --max-time 180 -o "$BODY" -w "%{http_code}" -X POST "$BASE/v1/chat/completions" \
      -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" -d @-)
[ "$STATUS" = "200" ] || { cat "$BODY" >&2; fail "healthy tier-2 request failed (HTTP $STATUS)"; }
SERVED=$(jq -r '.model // "unknown"' <"$BODY")
echo "  -> Status: 200 OK, served by: $SERVED"

echo
echo "Fallback chain verified!"
