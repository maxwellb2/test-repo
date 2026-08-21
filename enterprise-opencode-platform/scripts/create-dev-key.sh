#!/usr/bin/env bash
#
# Platform-team tool: mint a per-developer LiteLLM virtual key with a hard
# budget cap. The developer receives only this key; the OpenRouter key never
# leaves the proxy host.
#
# Usage:
#   scripts/create-dev-key.sh --alias jane --email jane@corp.com [--budget 50]
#   scripts/create-dev-key.sh --list
#   scripts/create-dev-key.sh --info sk-...
#   scripts/create-dev-key.sh --revoke sk-...
#
# Options:
#   --alias NAME     Human-readable key alias (required for creation)
#   --email ADDR     User id recorded against the key's spend
#   --budget USD     Spend cap per period (default 50)
#   --duration DUR   Budget window: 1d, 7d, 30d (default 30d)
#   --tiers LIST     Comma-separated tiers (default all three)
#   --rpm N          Requests per minute cap (default 120)
#   --tpm N          Tokens per minute cap (default 200000)
#   --proxy URL      Proxy base URL (default http://localhost:4000)
#   --list           List every provisioned key with its spend, then exit
#   --info KEY       Print spend and budget for an existing key, then exit
#   --revoke KEY     Permanently delete a key (offboarding), then exit
#   -h, --help       Show this message
#
# Requires LITELLM_MASTER_KEY in the environment (see docker/.env).
#
set -euo pipefail

ALIAS=""
EMAIL=""
BUDGET="50"
DURATION="30d"
TIERS="tier-1-fast,tier-2-balanced,tier-3-flagship"
PROXY="${LITELLM_PROXY_URL:-http://localhost:4000}"
RPM="120"
TPM="200000"
INFO_KEY=""
REVOKE_KEY=""
DO_LIST=0

die() { printf '\033[31merror\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -euo/d'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --alias)    ALIAS="${2:-}"; shift 2 ;;
    --email)    EMAIL="${2:-}"; shift 2 ;;
    --budget)   BUDGET="${2:-}"; shift 2 ;;
    --duration) DURATION="${2:-}"; shift 2 ;;
    --tiers)    TIERS="${2:-}"; shift 2 ;;
    --rpm)      RPM="${2:-}"; shift 2 ;;
    --tpm)      TPM="${2:-}"; shift 2 ;;
    --proxy)    PROXY="${2:-}"; shift 2 ;;
    --info)     INFO_KEY="${2:-}"; shift 2 ;;
    --revoke)   REVOKE_KEY="${2:-}"; shift 2 ;;
    --list)     DO_LIST=1; shift ;;
    -h|--help)  usage ;;
    *)          die "Unknown option: $1 (try --help)" ;;
  esac
done

[ -n "${LITELLM_MASTER_KEY:-}" ] || die "LITELLM_MASTER_KEY is not set. Source it from docker/.env."
command -v curl >/dev/null 2>&1 || die "curl is required."

if [ -n "$INFO_KEY" ]; then
  curl -fsS -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    "$PROXY/key/info?key=$INFO_KEY" \
    | { command -v jq >/dev/null 2>&1 && jq '.info | {key_alias, user_id, spend, max_budget, budget_duration, models}' || cat; }
  exit 0
fi

if [ "$DO_LIST" -eq 1 ]; then
  curl -fsS -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    "$PROXY/key/list?return_full_object=true&size=200" \
    | { command -v jq >/dev/null 2>&1 \
        && jq -r '["ALIAS","USER","SPEND","BUDGET","EXPIRES"], (.keys[]? | [
             (.key_alias // "-"), (.user_id // "-"),
             (.spend // 0 | tostring), (.max_budget // "none" | tostring),
             (.expires // "never" | tostring)]) | @tsv' | column -t \
        || cat; }
  exit 0
fi

if [ -n "$REVOKE_KEY" ]; then
  # Deletion is immediate and irreversible; spend history stays in Postgres.
  RESP=$(curl -fsS -X POST "$PROXY/key/delete" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"keys\": [\"$REVOKE_KEY\"]}") || die "Revocation failed. Is the proxy up at $PROXY?"
  printf 'Key revoked. The developer will get 401s on their next request.\n'
  printf '%s\n' "$RESP"
  exit 0
fi

[ -n "$ALIAS" ] || die "--alias is required."

MODELS_JSON=$(printf '%s' "$TIERS" | awk -F, '{for(i=1;i<=NF;i++){printf "%s\"%s\"", (i>1?",":""), $i}}')

PAYLOAD=$(cat <<EOF
{
  "key_alias": "$ALIAS",
  "user_id": "${EMAIL:-$ALIAS}",
  "models": [$MODELS_JSON],
  "max_budget": $BUDGET,
  "budget_duration": "$DURATION",
  "rpm_limit": $RPM,
  "tpm_limit": $TPM,
  "metadata": {"provisioned_by": "create-dev-key.sh", "team": "engineering"}
}
EOF
)

RESPONSE=$(curl -fsS -X POST "$PROXY/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD") || die "Key generation failed. Is the proxy up at $PROXY?"

if command -v jq >/dev/null 2>&1; then
  KEY=$(printf '%s' "$RESPONSE" | jq -r '.key')
else
  KEY=$(printf '%s' "$RESPONSE" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')
fi

[ -n "$KEY" ] && [ "$KEY" != "null" ] || die "Unexpected response: $RESPONSE"

cat <<EOF

Key created for $ALIAS
  budget:  \$$BUDGET per $DURATION
  limits:  $RPM req/min, $TPM tokens/min
  tiers:   $TIERS

Send this to the developer over a secret channel, not chat or email:

  $KEY

They run:
  DEVELOPER_TEAM_KEY=$KEY scripts/setup-dev-env.sh --repo /path/to/their/repo

EOF
