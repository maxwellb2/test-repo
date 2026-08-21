#!/usr/bin/env bash
#
# Validates every credential and external dependency the platform needs, before
# you try to start anything or hand keys to a developer.
#
# Each check makes a real authenticated call. "The key is set" is not the same
# as "the key works", and an unfunded OpenRouter account looks identical to a
# working one until the first request fails.
#
# Usage:
#   scripts/check-credentials.sh [--openrouter] [--langfuse] [--proxy] [--models]
#
# With no flags, runs every check. Reads docker/.env automatically if present.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT/docker/.env"

RUN_ALL=1
DO_OPENROUTER=0; DO_LANGFUSE=0; DO_PROXY=0; DO_MODELS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --openrouter) DO_OPENROUTER=1; RUN_ALL=0; shift ;;
    --langfuse)   DO_LANGFUSE=1;   RUN_ALL=0; shift ;;
    --proxy)      DO_PROXY=1;      RUN_ALL=0; shift ;;
    --models)     DO_MODELS=1;     RUN_ALL=0; shift ;;
    -h|--help)    sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -uo/d'; exit 0 ;;
    *)            printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done
if [ "$RUN_ALL" -eq 1 ]; then
  DO_OPENROUTER=1; DO_LANGFUSE=1; DO_PROXY=1; DO_MODELS=1
fi

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; FAILURES=$((FAILURES+1)); }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*" >&2; }
note() { printf '        %s\n' "$*"; }
group(){ printf '\n\033[1m%s\033[0m\n' "$*"; }

FAILURES=0
TIERS=("tier-1-fast" "tier-2-balanced" "tier-3-flagship")

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  printf 'Loaded %s\n' "$ENV_FILE"
else
  printf 'No docker/.env found; reading credentials from the environment.\n'
fi

PROXY_BASE="${LITELLM_PROXY_URL:-http://localhost:4000}"

# --- OpenRouter --------------------------------------------------------------
if [ "$DO_OPENROUTER" -eq 1 ]; then
  group "OpenRouter"
  if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    bad "OPENROUTER_API_KEY is not set"
    note "Create one at https://openrouter.ai/keys"
  else
    RESP=$(curl -fsS -m 15 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      https://openrouter.ai/api/v1/key 2>/dev/null)
    if [ -z "$RESP" ]; then
      bad "key rejected by OpenRouter"
      note "Check for a typo, or that the key has not been revoked."
    else
      ok "key authenticates"
      # An unfunded account authenticates fine and then 402s on first use, so
      # check the balance explicitly.
      CREDITS=$(curl -fsS -m 15 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        https://openrouter.ai/api/v1/credits 2>/dev/null)
      BAL=$(printf '%s' "$CREDITS" | node -e "
        let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
          try{const d=JSON.parse(s).data;
            console.log(((d.total_credits||0)-(d.total_usage||0)).toFixed(4));
          }catch{console.log('unknown')}})" 2>/dev/null)
      if [ "$BAL" = "unknown" ]; then
        warn "could not read credit balance"
      elif [ "$(printf '%s' "$BAL" | cut -d. -f1)" -le 0 ] 2>/dev/null; then
        bad "account has no credits (balance \$$BAL)"
        note "Every paid model will return HTTP 402 until you add credits at"
        note "https://openrouter.ai/settings/credits"
      else
        ok "credit balance \$$BAL"
      fi
    fi
  fi
fi

# --- Model availability and tool support -------------------------------------
if [ "$DO_MODELS" -eq 1 ]; then
  group "Model tiers"
  CONFIG="$ROOT/docker/litellm-config.yaml"
  if [ ! -f "$CONFIG" ]; then
    bad "missing $CONFIG"
  else
    CATALOG=$(curl -fsS -m 20 https://openrouter.ai/api/v1/models 2>/dev/null)
    if [ -z "$CATALOG" ]; then
      warn "could not reach the OpenRouter model catalogue; skipping"
    else
      for tier in "${TIERS[@]}"; do
        SLUG=$(awk -v t="$tier" '
          $0 ~ "model_name: " t {found=1; next}
          found && /model: openrouter\// {sub(/.*model: openrouter\//, ""); print; exit}
        ' "$CONFIG")
        if [ -z "$SLUG" ]; then
          bad "$tier: no model found in litellm-config.yaml"
          continue
        fi
        VERDICT=$(printf '%s' "$CATALOG" | SLUG="$SLUG" node -e "
          let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
            try{
              const m=JSON.parse(s).data.find(x=>x.id===process.env.SLUG);
              if(!m){console.log('MISSING');return}
              const tools=(m.supported_parameters||[]).includes('tools');
              console.log((tools?'TOOLS':'NOTOOLS')+' '+
                ((+m.pricing.prompt)*1e6).toFixed(3)+' '+
                ((+m.pricing.completion)*1e6).toFixed(3));
            }catch{console.log('MISSING')}})" 2>/dev/null)
        set -- $VERDICT
        case "${1:-MISSING}" in
          TOOLS)   ok "$tier -> $SLUG (tools ok, \$$2/\$$3 per 1M)" ;;
          NOTOOLS) bad "$tier -> $SLUG does NOT support tool calling"
                   note "This model cannot drive the agent loop. Pick another." ;;
          *)       bad "$tier -> $SLUG is not in the OpenRouter catalogue"
                   note "The slug was probably retired. Search the catalogue for a replacement." ;;
        esac
      done
    fi
  fi
fi

# --- Langfuse ----------------------------------------------------------------
if [ "$DO_LANGFUSE" -eq 1 ]; then
  group "Langfuse"
  LF_HOST="${LANGFUSE_HOST:-https://cloud.langfuse.com}"
  if [ -z "${LANGFUSE_PUBLIC_KEY:-}" ] || [ -z "${LANGFUSE_SECRET_KEY:-}" ]; then
    bad "LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY are not both set"
    note "Project Settings -> API Keys at $LF_HOST"
    note "Without these the proxy runs fine but you get zero trace visibility."
  else
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
      -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" \
      "$LF_HOST/api/public/projects" 2>/dev/null)
    case "$CODE" in
      200) ok "credentials accepted by $LF_HOST" ;;
      401|403) bad "Langfuse rejected the key pair (HTTP $CODE)"
               note "Public and secret key must come from the same project." ;;
      000) bad "could not reach $LF_HOST" ;;
      *)   warn "unexpected response from Langfuse (HTTP $CODE)" ;;
    esac
  fi
fi

# --- LiteLLM proxy -----------------------------------------------------------
if [ "$DO_PROXY" -eq 1 ]; then
  group "LiteLLM proxy"
  for var in LITELLM_MASTER_KEY LITELLM_SALT_KEY POSTGRES_PASSWORD; do
    if [ -z "${!var:-}" ]; then
      bad "$var is not set"
      note "docker compose will refuse to start without it."
    else
      ok "$var is set"
    fi
  done

  if curl -fsS -m 5 "$PROXY_BASE/health/liveliness" >/dev/null 2>&1; then
    ok "proxy is live at $PROXY_BASE"
    if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
      CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 10 \
        -H "Authorization: Bearer $LITELLM_MASTER_KEY" "$PROXY_BASE/models" 2>/dev/null)
      if [ "$CODE" = "200" ]; then
        ok "master key accepted"
      else
        bad "master key rejected by the proxy (HTTP $CODE)"
        note "The running proxy may predate your current .env; restart it."
      fi
    fi
    if [ -n "${DEVELOPER_TEAM_KEY:-}" ]; then
      SPEND=$(curl -fsS -m 10 -H "Authorization: Bearer $DEVELOPER_TEAM_KEY" \
        "$PROXY_BASE/key/info" 2>/dev/null | node -e "
          let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
            try{const i=JSON.parse(s).info;
              console.log('spend \$'+(i.spend??0)+' of \$'+(i.max_budget??'unlimited'));
            }catch{console.log('')}})" 2>/dev/null)
      [ -n "$SPEND" ] && ok "developer key valid ($SPEND)" || warn "DEVELOPER_TEAM_KEY set but not recognised by the proxy"
    fi
  else
    warn "proxy not reachable at $PROXY_BASE"
    note "Expected until you run: cd docker && docker compose up -d"
  fi
fi

# --- summary -----------------------------------------------------------------
echo ""
if [ "$FAILURES" -eq 0 ]; then
  printf '\033[32mAll credential checks passed.\033[0m\n'
  exit 0
fi
printf '\033[31m%s check(s) failed. Fix these before distributing keys.\033[0m\n' "$FAILURES" >&2
exit 1
