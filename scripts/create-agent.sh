#!/bin/bash
# create-agent.sh — Create a new OpenClaw agent with dedicated Slack app
#
# Usage: ./create-agent.sh <agent-id> <display-name> <emoji> <description> [slack-config-token]
#
# Example: ./create-agent.sh siteconfig Sanjay 🔧 "Backend cloud programmer - Go/Python/AWS"
#
# This script:
#   1. Creates the OpenClaw agent and workspace
#   2. Sets agent identity
#   3. Creates a Slack app via Manifest API (if config token provided)
#   4. Outputs install link and next steps
#
# Prerequisites:
#   - openclaw CLI available
#   - curl available
#   - Slack config token (xoxe.xoxp-...) for Manifest API (optional)

set -euo pipefail

AGENT_ID="${1:?Usage: $0 <agent-id> <display-name> <emoji> <description> [slack-config-token]}"
DISPLAY_NAME="${2:?Missing display name}"
EMOJI="${3:?Missing emoji}"
DESCRIPTION="${4:?Missing description}"
SLACK_CONFIG_TOKEN="${5:-}"

WORKSPACE="$HOME/.openclaw/workspace-${AGENT_ID}"
AGENT_DIR="$HOME/.openclaw/agents/${AGENT_ID}"

echo "=== Creating agent: ${DISPLAY_NAME} (${AGENT_ID}) ==="

# Step 1: Create OpenClaw agent
echo "[1/5] Creating OpenClaw agent..."
openclaw agents add "${AGENT_ID}" --workspace "${WORKSPACE}" 2>&1 || {
  echo "Agent may already exist, continuing..."
}

# Step 2: Set identity
echo "[2/5] Setting identity..."
openclaw agents set-identity --agent "${AGENT_ID}" --name "${DISPLAY_NAME}" --emoji "${EMOJI}" 2>&1

# Step 3: Create workspace files
echo "[3/5] Creating workspace files..."

cat > "${WORKSPACE}/IDENTITY.md" << EOF
# IDENTITY.md

- **Name:** ${DISPLAY_NAME}
- **Emoji:** ${EMOJI}
EOF

# Only create AGENTS.md if it doesn't exist or is the default template
if [ ! -f "${WORKSPACE}/AGENTS.md" ] || grep -q "BOOTSTRAP" "${WORKSPACE}/AGENTS.md" 2>/dev/null; then
  cat > "${WORKSPACE}/AGENTS.md" << EOF
# AGENTS.md - ${DISPLAY_NAME}'s Workspace

You are ${DISPLAY_NAME}. This is your workspace.

## Session Startup

1. Read \`SOUL.md\` — your identity and operating principles
2. Read \`USER.md\` — who you're helping

## Red Lines

- Don't run destructive commands without confirmation
- When in doubt, ask
EOF
fi

# Remove BOOTSTRAP.md if present
rm -f "${WORKSPACE}/BOOTSTRAP.md"

echo "  → IDENTITY.md created"
echo "  → BOOTSTRAP.md removed (if present)"
echo "  → Note: Create SOUL.md manually with the agent's personality"

# Step 4: Setup git identity
echo "[4/5] Setting up git identity..."
git -C "${WORKSPACE}" config user.name "${DISPLAY_NAME} (${AGENT_ID})"
git -C "${WORKSPACE}" config user.email "${AGENT_ID}@damesoftware.com"

# Step 5: Create Slack app (if config token provided)
if [ -n "${SLACK_CONFIG_TOKEN}" ]; then
  echo "[5/5] Creating Slack app via Manifest API..."
  
  SCOPES='["chat:write","chat:write.customize","channels:history","channels:read","groups:history","im:history","im:read","im:write","mpim:history","mpim:read","mpim:write","users:read","app_mentions:read","assistant:write","reactions:read","reactions:write","pins:read","pins:write","emoji:read","commands","files:read","files:write"]'
  
  EVENTS='["app_mention","message.channels","message.groups","message.im","message.mpim","reaction_added","reaction_removed","member_joined_channel","member_left_channel","channel_rename","pin_added","pin_removed"]'
  
  RESPONSE=$(curl -s -X POST https://slack.com/api/apps.manifest.create \
    -H "Authorization: Bearer ${SLACK_CONFIG_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"manifest\": {
        \"display_information\": {
          \"name\": \"${DISPLAY_NAME}\",
          \"description\": \"${DESCRIPTION}\"
        },
        \"features\": {
          \"bot_user\": {
            \"display_name\": \"${DISPLAY_NAME}\",
            \"always_online\": true
          },
          \"app_home\": {
            \"messages_tab_enabled\": true,
            \"messages_tab_read_only_enabled\": false
          }
        },
        \"oauth_config\": {
          \"scopes\": {
            \"bot\": ${SCOPES}
          }
        },
        \"settings\": {
          \"socket_mode_enabled\": true,
          \"event_subscriptions\": {
            \"bot_events\": ${EVENTS}
          }
        }
      }
    }")
  
  OK=$(echo "${RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok','false'))" 2>/dev/null)
  
  if [ "${OK}" = "True" ] || [ "${OK}" = "true" ]; then
    APP_ID=$(echo "${RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['app_id'])")
    CLIENT_ID=$(echo "${RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['credentials']['client_id'])")
    OAUTH_URL=$(echo "${RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['oauth_authorize_url'])")
    
    echo ""
    echo "=== Slack App Created ==="
    echo "App ID:     ${APP_ID}"
    echo "Client ID:  ${CLIENT_ID}"
    echo ""
    echo "=== MANUAL STEPS REQUIRED ==="
    echo ""
    echo "1. Install the app to your workspace:"
    echo "   ${OAUTH_URL}"
    echo ""
    echo "2. Get Bot Token (xoxb-...):"
    echo "   https://api.slack.com/apps/${APP_ID}/oauth"
    echo ""
    echo "3. Generate App-Level Token (xapp-...):"
    echo "   https://api.slack.com/apps/${APP_ID}/general"
    echo "   → App-Level Tokens → Generate → scope: connections:write"
    echo ""
    echo "4. Add to OpenClaw config:"
    echo "   openclaw config set channels.slack.accounts.${AGENT_ID}.botToken 'xoxb-...'"
    echo "   openclaw config set channels.slack.accounts.${AGENT_ID}.appToken 'xapp-...'"
    echo ""
    echo "5. Add routing binding (in openclaw.json):"
    echo "   { \"agentId\": \"${AGENT_ID}\", \"match\": { \"channel\": \"slack\", \"accountId\": \"${AGENT_ID}\" } }"
    echo ""
    echo "6. Reload gateway:"
    echo "   kill -HUP 1  # in container"
    echo "   # or: openclaw gateway restart"
    echo ""
    echo "7. Approve pairing when DM'd:"
    echo "   openclaw pairing approve slack <CODE>"
  else
    echo "ERROR: Slack app creation failed"
    echo "${RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d, indent=2))" 2>/dev/null || echo "${RESPONSE}"
  fi
else
  echo "[5/5] Skipping Slack app creation (no config token provided)"
  echo ""
  echo "=== Agent Created ==="
  echo "To create a Slack app later, run:"
  echo "  $0 ${AGENT_ID} '${DISPLAY_NAME}' '${EMOJI}' '${DESCRIPTION}' \$SLACK_CONFIG_TOKEN"
fi

echo ""
echo "=== Summary ==="
echo "Agent ID:   ${AGENT_ID}"
echo "Name:       ${DISPLAY_NAME} ${EMOJI}"
echo "Workspace:  ${WORKSPACE}"
echo "Git:        ${DISPLAY_NAME} (${AGENT_ID}) <${AGENT_ID}@damesoftware.com>"
echo ""
echo "Next: Create ${WORKSPACE}/SOUL.md with the agent's personality and role."
