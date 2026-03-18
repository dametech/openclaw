#!/bin/bash
#
# setup-1password.sh — Create/refresh auth-profiles.json for all agents from 1Password
#
# Pulls the Anthropic API key from 1Password and writes auth-profiles.json
# for every agent. Run this after a fresh deploy or if auth files are lost.
#
# Prerequisites:
#   - OP_SERVICE_ACCOUNT_TOKEN set in environment
#   - op CLI available at ~/.openclaw/bin/op or on PATH
#   - Access to the "Infrastructure" vault in 1Password
#
# Usage:
#   ./setup-1password.sh              # auto-detect agents
#   ./setup-1password.sh davo edgex   # specific agents only
#

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────
OPENCLAW_DIR="${HOME}/.openclaw"
AGENTS_DIR="${OPENCLAW_DIR}/agents"
OP_BIN="${OPENCLAW_DIR}/bin/op"
VAULT="Infrastructure"
ITEM="Anthropic API Key Openclaw"
FIELD="notesPlain"

# ── Helpers ────────────────────────────────────────────────────────
log() { echo "[1password-setup] $*"; }
err() { echo "[1password-setup] ERROR: $*" >&2; }

# ── Preflight ──────────────────────────────────────────────────────
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    err "OP_SERVICE_ACCOUNT_TOKEN is not set"
    exit 1
fi

# Find op binary
OP=""
if [ -x "$OP_BIN" ]; then
    OP="$OP_BIN"
elif command -v op &>/dev/null; then
    OP="op"
else
    err "op CLI not found at $OP_BIN or on PATH"
    exit 1
fi

log "Using op CLI: $OP ($($OP --version))"

# ── Verify 1Password access ───────────────────────────────────────
log "Verifying 1Password access..."
if ! $OP whoami &>/dev/null; then
    err "Cannot authenticate with 1Password. Check OP_SERVICE_ACCOUNT_TOKEN."
    exit 1
fi

# ── Fetch API key ──────────────────────────────────────────────────
log "Fetching Anthropic API key from vault '$VAULT'..."
API_KEY=$($OP item get "$ITEM" --vault "$VAULT" --fields "$FIELD" 2>/dev/null)

if [ -z "$API_KEY" ]; then
    err "Failed to fetch API key from 1Password (vault: $VAULT, item: $ITEM, field: $FIELD)"
    exit 1
fi

log "API key fetched (${#API_KEY} chars)"

# ── Determine agents ──────────────────────────────────────────────
if [ $# -gt 0 ]; then
    AGENTS=("$@")
else
    # Auto-detect from agents directory
    AGENTS=()
    for dir in "$AGENTS_DIR"/*/; do
        if [ -d "$dir" ]; then
            agent=$(basename "$dir")
            AGENTS+=("$agent")
        fi
    done
fi

if [ ${#AGENTS[@]} -eq 0 ]; then
    err "No agents found in $AGENTS_DIR"
    exit 1
fi

log "Agents: ${AGENTS[*]}"

# ── Write auth-profiles.json ──────────────────────────────────────
for agent in "${AGENTS[@]}"; do
    agent_dir="$AGENTS_DIR/$agent/agent"
    auth_file="$agent_dir/auth-profiles.json"

    mkdir -p "$agent_dir"

    cat > "$auth_file" << EOF
{
  "version": 1,
  "profiles": {
    "anthropic:claude-cli": {
      "type": "api_key",
      "mode": "static",
      "key": "$API_KEY",
      "provider": "anthropic"
    }
  }
}
EOF

    chmod 600 "$auth_file"
    log "  ✓ $agent"
done

# ── Done ───────────────────────────────────────────────────────────
log ""
log "Auth profiles written for ${#AGENTS[@]} agents."
log "Run 'openclaw secrets reload' or restart the pod to pick up changes."
