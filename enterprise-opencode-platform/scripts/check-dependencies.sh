#!/usr/bin/env bash
#
# Validates that this machine has everything the OpenCode platform needs.
# Exits non-zero if a required tool is missing. Missing LSPs are warnings only:
# they degrade completion quality but nothing breaks without them.
#
# Usage: check-dependencies.sh [--quiet]
#
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

pass() { [ "$QUIET" -eq 1 ] || printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*" >&2; }
fail() { printf '  \033[31mmiss\033[0m  %s\n' "$*" >&2; }

missing_required=0
missing_optional=0

# tool:reason
REQUIRED=(
  "git:version control and hook installation"
  "curl:CLI installer and proxy health checks"
  "node:JSON config merging during setup"
  "npm:LSP and tooling installation"
)

OPTIONAL=(
  "opencode:the agent itself (installed by setup-dev-env.sh)"
  "docker:running the LiteLLM proxy locally"
  "jq:inspecting proxy responses"
)

# lsp-binary:install hint
LSP_TOOLS=(
  "typescript-language-server:npm i -g typescript-language-server typescript"
  "pyright:npm i -g pyright"
  "gopls:go install golang.org/x/tools/gopls@latest"
  "rust-analyzer:rustup component add rust-analyzer"
)

[ "$QUIET" -eq 1 ] || echo "Required tools:"
for entry in "${REQUIRED[@]}"; do
  tool="${entry%%:*}"; reason="${entry#*:}"
  if command -v "$tool" >/dev/null 2>&1; then
    pass "$tool"
  else
    fail "$tool - required for $reason"
    missing_required=$((missing_required + 1))
  fi
done

[ "$QUIET" -eq 1 ] || echo "Optional tools:"
for entry in "${OPTIONAL[@]}"; do
  tool="${entry%%:*}"; reason="${entry#*:}"
  if command -v "$tool" >/dev/null 2>&1; then
    pass "$tool"
  else
    warn "$tool - needed for $reason"
    missing_optional=$((missing_optional + 1))
  fi
done

[ "$QUIET" -eq 1 ] || echo "Language servers:"
for entry in "${LSP_TOOLS[@]}"; do
  lsp="${entry%%:*}"; hint="${entry#*:}"
  if command -v "$lsp" >/dev/null 2>&1; then
    pass "$lsp"
  else
    warn "$lsp missing - context quality will drop for that language. Install: $hint"
    missing_optional=$((missing_optional + 1))
  fi
done

# docker compose is a plugin, not a binary; check it separately.
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    pass "docker compose"
  else
    warn "docker compose plugin missing - cannot start the proxy stack"
    missing_optional=$((missing_optional + 1))
  fi
fi

echo ""
if [ "$missing_required" -gt 0 ]; then
  printf '\033[31m%s required tool(s) missing. Install them and re-run.\033[0m\n' "$missing_required" >&2
  exit 1
fi

if [ "$missing_optional" -gt 0 ]; then
  printf '\033[33mAll required tools present. %s optional item(s) missing.\033[0m\n' "$missing_optional"
else
  printf '\033[32mAll dependencies present.\033[0m\n'
fi
exit 0
