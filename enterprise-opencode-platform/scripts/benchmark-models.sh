#!/usr/bin/env bash
#
# Phase 0 model benchmark.
#
# Answers one question per model: can it actually drive the OpenCode agent loop?
# Each run gets a clean copy of a repo with a failing test suite and a bug, and
# is scored on whether the suite passes afterwards without the tests being
# edited. Reliability is the point, so each model runs several times.
#
# Usage:
#   scripts/benchmark-models.sh [options]
#
# Options:
#   --models LIST   Comma-separated models (default: the three tier candidates)
#   --runs N        Runs per model (default 3)
#   --timeout SECS  Per-run wall-clock limit (default 300)
#   --keep          Keep per-run working directories and event logs
#   --out DIR       Results directory (default tests/phase0/results)
#   -h, --help      Show this message
#
# Models are addressed through OpenCode's built-in OpenRouter provider, so this
# runs before any proxy exists. Point it at the proxy later with
# --models custom-proxy/tier-2-balanced to re-validate the same task end to end.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE0="$ROOT/tests/phase0"
FIXTURE="$PHASE0/fixture"

MODELS="openrouter/qwen/qwen3-coder-30b-a3b-instruct,openrouter/deepseek/deepseek-chat,openrouter/anthropic/claude-sonnet-4.6"
RUNS=3
TIMEOUT=300
KEEP=0
OUT="$PHASE0/results"

die() { printf '\033[31merror\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -uo/d'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --models)  MODELS="${2:-}"; shift 2 ;;
    --runs)    RUNS="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    --keep)    KEEP=1; shift ;;
    -h|--help) usage ;;
    *)         die "Unknown option: $1 (try --help)" ;;
  esac
done

command -v opencode >/dev/null 2>&1 || die "opencode CLI not found."
command -v node >/dev/null 2>&1 || die "node is required to run the fixture tests."
[ -d "$FIXTURE" ] || die "Fixture missing at $FIXTURE"

TASK=$(cat "$PHASE0/task.txt")
mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M%S)
CSV="$OUT/benchmark-$STAMP.csv"
echo "model,run,passed,tests_edited,seconds,cost_usd,input_tokens,output_tokens,tool_calls,error" > "$CSV"

WORK=$(mktemp -d)
cleanup() { [ "$KEEP" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$TIMEOUT" "$@"
  else "$@"
  fi
}

printf '\033[1mPhase 0 benchmark\033[0m  %s runs per model, %ss timeout\n\n' "$RUNS" "$TIMEOUT"

IFS=',' read -r -a MODEL_ARRAY <<< "$MODELS"

for model in "${MODEL_ARRAY[@]}"; do
  printf '\033[1m%s\033[0m\n' "$model"

  for run in $(seq 1 "$RUNS"); do
    slug=$(printf '%s-%s' "$model" "$run" | tr '/:.' '---')
    repo="$WORK/$slug"
    events="$OUT/events-$slug-$STAMP.json"

    # A clean checkout per run, and a commit so edits to test/ are detectable.
    rm -rf "$repo"
    mkdir -p "$repo"
    cp -R "$FIXTURE/." "$repo/"
    git -C "$repo" init -q
    git -C "$repo" config user.email bench@example.com
    git -C "$repo" config user.name Benchmark
    git -C "$repo" add -A
    git -C "$repo" commit -qm "fixture"

    start=$SECONDS
    (cd "$repo" && run_with_timeout opencode run --auto \
        --model "$model" \
        --format json \
        --title "phase0 $model run$run" \
        "$TASK" > "$events" 2>&1)
    rc=$?
    elapsed=$((SECONDS - start))

    if (cd "$repo" && npm test >/dev/null 2>&1); then passed=yes; else passed=no; fi
    if [ -n "$(git -C "$repo" status --porcelain test/ 2>/dev/null)" ]; then edited=yes; else edited=no; fi

    metrics=$(node "$PHASE0/score.mjs" "$events" --line 2>/dev/null || echo "- - - 0 scorer_failed")
    read -r cost intok outtok tools err <<< "$metrics"

    if [ "$rc" -ne 0 ] && [ "$err" = "-" ]; then
      err="exit_${rc}_timeout_or_crash"
    fi

    if [ "$passed" = "yes" ] && [ "$edited" = "no" ]; then
      verdict='\033[32mPASS\033[0m'
    elif [ "$edited" = "yes" ]; then
      verdict='\033[31mCHEAT\033[0m'
    else
      verdict='\033[31mFAIL\033[0m'
    fi
    printf "  run %s  $verdict  %3ss  %8s USD  %4s tool calls  %s\n" \
      "$run" "$elapsed" "$cost" "$tools" "$err"

    echo "$model,$run,$passed,$edited,$elapsed,$cost,$intok,$outtok,$tools,\"$err\"" >> "$CSV"
    [ "$KEEP" -eq 1 ] || rm -f "$events"
  done
  echo ""
done

printf '\033[1mSummary\033[0m\n'
node -e "
const fs=require('fs');
const rows=fs.readFileSync('$CSV','utf8').trim().split('\n').slice(1)
  .map(l=>{const m=l.match(/^([^,]+),(\d+),(\w+),(\w+),(\d+),([^,]*),([^,]*),([^,]*),(\d+),\"(.*)\"\$/);
    return m?{model:m[1],passed:m[3]==='yes',edited:m[4]==='yes',sec:+m[5],cost:parseFloat(m[6])||0}:null}).filter(Boolean);
const byModel={};
for(const r of rows){(byModel[r.model]=byModel[r.model]||[]).push(r)}
const pad=(s,n)=>String(s).padEnd(n);
console.log('  '+pad('model',52)+pad('pass',8)+pad('cheat',7)+pad('avg s',7)+'avg \$');
for(const [m,rs] of Object.entries(byModel)){
  const ok=rs.filter(r=>r.passed&&!r.edited).length;
  const cheat=rs.filter(r=>r.edited).length;
  const avgS=(rs.reduce((a,r)=>a+r.sec,0)/rs.length).toFixed(0);
  const avgC=(rs.reduce((a,r)=>a+r.cost,0)/rs.length);
  console.log('  '+pad(m,52)+pad(ok+'/'+rs.length,8)+pad(cheat,7)+pad(avgS,7)+(avgC?avgC.toFixed(5):'-'));
}
"
echo ""
echo "  Full results: $CSV"
echo ""
echo "  A tier candidate needs a clean sweep with zero cheats. Anything that"
echo "  edits test/ to make the suite pass is disqualified regardless of speed."
