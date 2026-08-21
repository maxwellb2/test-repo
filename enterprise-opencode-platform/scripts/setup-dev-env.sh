#!/usr/bin/env bash
#
# Enterprise OpenCode Platform - developer onboarding.
#
# Installs the OpenCode CLI, writes the developer's proxy key to the global
# config, drops the shared project config into the target repo, and registers
# the AI pre-commit hook. Target is under three minutes end to end.
#
# Usage:
#   scripts/setup-dev-env.sh [options]
#
# Options:
#   --dev-key KEY      Developer Team Key. Falls back to $DEVELOPER_TEAM_KEY,
#                      then to an interactive prompt.
#   --proxy-url URL    LiteLLM base URL (default http://localhost:4000/v1)
#   --repo PATH        Repo to configure (default: current directory)
#   --non-interactive  Never prompt; fail if the key is not already supplied
#   --skip-install     Do not install the OpenCode CLI
#   --no-hooks         Do not register the git pre-commit hook
#   -h, --help         Show this message
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
START_TIME=$SECONDS

DEV_KEY="${DEVELOPER_TEAM_KEY:-}"
PROXY_URL="${LITELLM_BASE_URL:-http://localhost:4000/v1}"
TARGET_REPO="$PWD"
INTERACTIVE=1
DO_INSTALL=1
DO_HOOKS=1

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn()  { printf '  \033[33mwarn\033[0m  %s\n' "$*" >&2; }
die()   { printf '\033[31merror\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -euo/d'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dev-key)         DEV_KEY="${2:-}"; shift 2 ;;
    --proxy-url)       PROXY_URL="${2:-}"; shift 2 ;;
    --repo)            TARGET_REPO="${2:-}"; shift 2 ;;
    --non-interactive) INTERACTIVE=0; shift ;;
    --skip-install)    DO_INSTALL=0; shift ;;
    --no-hooks)        DO_HOOKS=0; shift ;;
    -h|--help)         usage ;;
    *)                 die "Unknown option: $1 (try --help)" ;;
  esac
done

bold "Enterprise OpenCode Platform - developer setup"
echo ""

# --- [1/5] dependencies ------------------------------------------------------
bold "[1/5] Checking system dependencies"
if ! bash "$SCRIPT_DIR/check-dependencies.sh"; then
  die "Required dependencies are missing. See the output above."
fi
echo ""

# --- [2/5] OpenCode CLI ------------------------------------------------------
bold "[2/5] Installing OpenCode CLI"
if command -v opencode >/dev/null 2>&1; then
  ok "already installed ($(opencode --version 2>/dev/null || echo 'unknown version'))"
elif [ "$DO_INSTALL" -eq 0 ]; then
  warn "not installed, and --skip-install was passed"
else
  info "downloading from https://opencode.ai/install"
  curl -fsSL https://opencode.ai/install | bash
  # The installer drops the binary in ~/.opencode/bin, which may not be on PATH
  # in this shell yet.
  export PATH="$HOME/.opencode/bin:$PATH"
  command -v opencode >/dev/null 2>&1 \
    && ok "installed ($(opencode --version 2>/dev/null))" \
    || warn "installed, but 'opencode' is not on PATH. Add \$HOME/.opencode/bin to your PATH."
fi
echo ""

# --- [3/5] developer key -----------------------------------------------------
bold "[3/5] Configuring your Developer Team Key"
if [ -z "$DEV_KEY" ]; then
  if [ "$INTERACTIVE" -eq 0 ]; then
    die "No key supplied. Pass --dev-key or set DEVELOPER_TEAM_KEY."
  fi
  info "Ask your platform team for a key, or mint one with scripts/create-dev-key.sh"
  read -rsp "  Enter assigned Developer Team Key: " DEV_KEY
  echo ""
fi
[ -n "$DEV_KEY" ] || die "Developer Team Key cannot be empty."
case "$DEV_KEY" in
  sk-*) ;;
  *) warn "key does not start with 'sk-'; continuing anyway" ;;
esac

GLOBAL_CONFIG_DIR="$HOME/.config/opencode"
GLOBAL_CONFIG="$GLOBAL_CONFIG_DIR/opencode.json"
mkdir -p "$GLOBAL_CONFIG_DIR"

if [ -f "$GLOBAL_CONFIG" ]; then
  BACKUP="$GLOBAL_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  cp "$GLOBAL_CONFIG" "$BACKUP"
  info "backed up existing config to $(basename "$BACKUP")"
fi

# Merge rather than overwrite: developers accumulate personal settings
# (keybinds, themes, other providers) that setup must not blow away.
CONFIG_PATH="$GLOBAL_CONFIG" DEV_KEY="$DEV_KEY" PROXY_URL="$PROXY_URL" node <<'NODE'
const fs = require("fs");
const path = process.env.CONFIG_PATH;

let config = {};
if (fs.existsSync(path)) {
  try {
    config = JSON.parse(fs.readFileSync(path, "utf8"));
  } catch (err) {
    console.error(`  warn  existing config is not valid JSON (${err.message}); starting fresh`);
    config = {};
  }
}

config["$schema"] = "https://opencode.ai/config.json";
config.provider = config.provider || {};
config.provider["custom-proxy"] = {
  ...(config.provider["custom-proxy"] || {}),
  npm: "@ai-sdk/openai-compatible",
  name: "Enterprise LiteLLM Proxy",
  options: {
    ...((config.provider["custom-proxy"] || {}).options || {}),
    baseURL: process.env.PROXY_URL,
    apiKey: process.env.DEV_KEY,
  },
};

fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
NODE

chmod 600 "$GLOBAL_CONFIG"
ok "key written to $GLOBAL_CONFIG (mode 600)"
ok "proxy set to $PROXY_URL"
echo ""

# --- [4/5] repository config -------------------------------------------------
bold "[4/5] Configuring repository"
if [ ! -d "$TARGET_REPO" ]; then
  die "Target repo does not exist: $TARGET_REPO"
fi
TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"

if [ "$TARGET_REPO" = "$PLATFORM_DIR" ]; then
  info "target is the platform repo itself; skipping template copy"
else
  for file in opencode.json AGENTS.md; do
    if [ -f "$TARGET_REPO/$file" ]; then
      warn "$file already exists in the repo, leaving it alone"
    else
      cp "$PLATFORM_DIR/templates/$file" "$TARGET_REPO/$file"
      ok "installed $file"
    fi
  done
fi

# The local override file holds a key, so it must never be committed.
if [ -d "$TARGET_REPO/.git" ] || git -C "$TARGET_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  GITIGNORE="$TARGET_REPO/.gitignore"
  if ! grep -qxF "opencode.local.json" "$GITIGNORE" 2>/dev/null; then
    printf '\n# OpenCode per-developer overrides (contains a proxy key)\nopencode.local.json\n' >> "$GITIGNORE"
    ok "added opencode.local.json to .gitignore"
  fi
fi
echo ""

# --- [5/5] git hooks ---------------------------------------------------------
bold "[5/5] Registering git hooks"
if [ "$DO_HOOKS" -eq 0 ]; then
  info "skipped (--no-hooks)"
elif ! git -C "$TARGET_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  warn "$TARGET_REPO is not a git repository; skipping hook installation"
else
  HOOKS_DIR="$TARGET_REPO/.githooks"
  mkdir -p "$HOOKS_DIR"
  cp "$PLATFORM_DIR/hooks/pre-commit" "$HOOKS_DIR/pre-commit"
  chmod +x "$HOOKS_DIR/pre-commit"
  # core.hooksPath keeps the hook in version control instead of in .git/hooks,
  # where it would be invisible and unshareable.
  git -C "$TARGET_REPO" config core.hooksPath .githooks
  ok "pre-commit hook registered via core.hooksPath=.githooks"
fi
echo ""

# --- proxy reachability ------------------------------------------------------
HEALTH_URL="${PROXY_URL%/v1}/health/liveliness"
if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null 2>&1; then
  ok "LiteLLM proxy is reachable at $HEALTH_URL"
else
  warn "LiteLLM proxy not reachable at $HEALTH_URL"
  warn "Start it with: cd $PLATFORM_DIR/docker && docker compose up -d"
fi

ELAPSED=$((SECONDS - START_TIME))
echo ""
bold "OpenCode configuration successfully initialized in ${ELAPSED}s."
echo ""
info "Next: run 'opencode' in $TARGET_REPO"
info "Tiers: tier-1-fast (cheap) | tier-2-balanced (default) | tier-3-flagship (hard problems)"
