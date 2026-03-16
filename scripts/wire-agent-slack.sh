#!/bin/bash
# wire-agent-slack.sh — Wire a Slack account to an OpenClaw agent
#
# Usage: ./wire-agent-slack.sh <agent-id> <bot-token> <app-token>
#
# Example: ./wire-agent-slack.sh siteconfig xoxb-... xapp-...
#
# This script:
#   1. Adds the Slack account to openclaw.json
#   2. Adds the routing binding
#   3. Triggers a config reload
#   4. Verifies the connection
#
# Prerequisites:
#   - openclaw CLI available
#   - python3 available
#   - Agent must already exist (run create-agent.sh first)

set -euo pipefail

AGENT_ID="${1:?Usage: $0 <agent-id> <bot-token> <app-token>}"
BOT_TOKEN="${2:?Missing bot token (xoxb-...)}"
APP_TOKEN="${3:?Missing app-level token (xapp-...)}"

CONFIG_FILE="$HOME/.openclaw/openclaw.json"

echo "=== Wiring Slack account for agent: ${AGENT_ID} ==="

# Validate tokens
if [[ ! "${BOT_TOKEN}" == xoxb-* ]]; then
  echo "ERROR: Bot token must start with xoxb-"
  exit 1
fi
if [[ ! "${APP_TOKEN}" == xapp-* ]]; then
  echo "ERROR: App-level token must start with xapp-"
  exit 1
fi

# Verify agent exists
if ! openclaw agents list 2>&1 | grep -q "${AGENT_ID}"; then
  echo "ERROR: Agent '${AGENT_ID}' not found. Run create-agent.sh first."
  exit 1
fi

# Test bot token
echo "[1/4] Validating bot token..."
AUTH_RESULT=$(curl -s -X POST https://slack.com/api/auth.test \
  -H "Authorization: Bearer ${BOT_TOKEN}" \
  -H "Content-Type: application/json")
AUTH_OK=$(echo "${AUTH_RESULT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ok','false'))")
if [ "${AUTH_OK}" != "True" ] && [ "${AUTH_OK}" != "true" ]; then
  echo "ERROR: Bot token validation failed"
  echo "${AUTH_RESULT}" | python3 -m json.tool 2>/dev/null || echo "${AUTH_RESULT}"
  exit 1
fi
BOT_USER=$(echo "${AUTH_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user','unknown'))")
echo "  → Bot token valid (user: ${BOT_USER})"

# Add Slack account and binding to config
echo "[2/4] Updating openclaw.json..."
python3 << PYEOF
import json

with open("${CONFIG_FILE}") as f:
    config = json.load(f)

# Ensure accounts structure exists
if "accounts" not in config.get("channels", {}).get("slack", {}):
    config["channels"]["slack"]["accounts"] = {}

# Add account
config["channels"]["slack"]["accounts"]["${AGENT_ID}"] = {
    "botToken": "${BOT_TOKEN}",
    "appToken": "${APP_TOKEN}"
}

# Add binding (before the main/default fallback if present)
if "bindings" not in config:
    config["bindings"] = []

# Check if binding already exists
existing = [b for b in config["bindings"] 
            if b.get("agentId") == "${AGENT_ID}" and 
               b.get("match", {}).get("accountId") == "${AGENT_ID}"]

if not existing:
    new_binding = {
        "agentId": "${AGENT_ID}",
        "match": {"channel": "slack", "accountId": "${AGENT_ID}"}
    }
    # Insert before last entry (usually the main fallback)
    if len(config["bindings"]) > 0:
        config["bindings"].insert(-1, new_binding)
    else:
        config["bindings"].append(new_binding)
    print("  → Binding added")
else:
    print("  → Binding already exists")

with open("${CONFIG_FILE}", "w") as f:
    json.dump(config, f, indent=2)
print("  → Config updated")
PYEOF

# Reload gateway
echo "[3/4] Reloading gateway..."
kill -HUP 1 2>/dev/null || echo "  → HUP signal failed (may need manual restart)"
sleep 3

# Verify
echo "[4/4] Verifying connection..."
STATUS=$(openclaw channels status --probe 2>&1 | grep -i "${AGENT_ID}" || echo "NOT FOUND")
echo "  → ${STATUS}"

echo ""
echo "=== Done ==="
echo "Agent ${AGENT_ID} is wired to Slack account '${BOT_USER}'."
echo ""
echo "First DM will require pairing approval:"
echo "  openclaw pairing approve slack <CODE>"
