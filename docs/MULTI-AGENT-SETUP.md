# Multi-Agent Setup Guide

End-to-end guide for setting up OpenClaw agents with dedicated Slack identities. Each agent gets its own Slack bot, workspace, git identity, and personality.

## Architecture

```
OpenClaw Gateway (single container)
├── 🦞 Claw (main)       → Slack: "Claw"       → Platform admin
├── ⎈  Davo (davo)       → Slack: "Davo"       → DevOps / K8s
├── 🔧 Sanjay (siteconfig) → Slack: "Sanjay"   → Backend / AWS
├── 🎨 Mia (siteuis)     → Slack: "Mia"        → Frontend / UIs
├── 📡 Eddie (edgex)     → Slack: "Eddie"       → EdgeX / Modbus
├── ⛏️ Jett (minercode)  → Slack: "Jett"        → Mining devices
└── 🔍 Ruby (minermaint) → Slack: "Ruby"        → Maintenance ops
```

Each agent has:
- **Isolated workspace** — own SOUL.md, IDENTITY.md, AGENTS.md
- **Isolated sessions** — no cross-talk between agents
- **Own Slack bot** — appears as a separate user in Slack
- **Own git identity** — commits traceable per agent

## Prerequisites

- Running OpenClaw instance
- Slack workspace admin access
- Slack Config Token (`xoxe.xoxp-...`) for the Manifest API
- GitHub Personal Access Token (for repo access)

### Getting a Slack Config Token

1. Go to https://api.slack.com/reference/manifests#config-tokens
2. Click "Generate Token" and select your workspace
3. Save both the access token and refresh token securely

## Quick Start: Create an Agent

```bash
# Full setup with Slack app creation
./scripts/create-agent.sh <agent-id> "<Name>" "<emoji>" "<description>" $SLACK_CONFIG_TOKEN

# Example
./scripts/create-agent.sh siteconfig "Sanjay" "🔧" "Backend cloud programmer - Go/Python/AWS" $SLACK_CONFIG_TOKEN
```

Then follow the manual steps output by the script (install app, grab tokens).

## Step-by-Step: Manual Process

### 1. Create the OpenClaw Agent

```bash
openclaw agents add <agent-id> --workspace ~/.openclaw/workspace-<agent-id>
openclaw agents set-identity --agent <agent-id> --name "<Name>" --emoji "<emoji>"
```

### 2. Create Workspace Files

Each agent needs at minimum:

**SOUL.md** — Personality, role, expertise, boundaries
**IDENTITY.md** — Name, emoji, creature description
**AGENTS.md** — Workspace rules, startup instructions
**USER.md** — Copy from main workspace (who they're helping)

Remove `BOOTSTRAP.md` if present (it makes agents think they're unconfigured).

### 3. Create Slack App via API

```bash
curl -s -X POST https://slack.com/api/apps.manifest.create \
  -H "Authorization: Bearer $SLACK_CONFIG_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "manifest": {
      "display_information": {
        "name": "<Agent Name>",
        "description": "<Role description>"
      },
      "features": {
        "bot_user": { "display_name": "<Agent Name>", "always_online": true },
        "app_home": { "messages_tab_enabled": true, "messages_tab_read_only_enabled": false }
      },
      "oauth_config": {
        "scopes": {
          "bot": [
            "chat:write", "chat:write.customize", "channels:history", "channels:read",
            "groups:history", "im:history", "im:read", "im:write",
            "mpim:history", "mpim:read", "mpim:write", "users:read",
            "app_mentions:read", "assistant:write", "reactions:read", "reactions:write",
            "pins:read", "pins:write", "emoji:read", "commands", "files:read", "files:write"
          ]
        }
      },
      "settings": {
        "socket_mode_enabled": true,
        "event_subscriptions": {
          "bot_events": [
            "app_mention", "message.channels", "message.groups", "message.im", "message.mpim",
            "reaction_added", "reaction_removed", "member_joined_channel", "member_left_channel",
            "channel_rename", "pin_added", "pin_removed"
          ]
        }
      }
    }
  }'
```

### 4. Install App & Get Tokens (UI Required)

1. **Install**: Open the `oauth_authorize_url` from the API response → click Allow
2. **Bot Token**: `https://api.slack.com/apps/<APP_ID>/oauth` → copy `xoxb-...`
3. **App-Level Token**: `https://api.slack.com/apps/<APP_ID>/general` → Generate → scope `connections:write` → copy `xapp-...`

### 5. Wire Into OpenClaw

```bash
./scripts/wire-agent-slack.sh <agent-id> <bot-token> <app-token>
```

Or manually add to `openclaw.json`:

```json5
{
  "channels": {
    "slack": {
      "accounts": {
        "<agent-id>": {
          "botToken": "xoxb-...",
          "appToken": "xapp-..."
        }
      }
    }
  },
  "bindings": [
    { "agentId": "<agent-id>", "match": { "channel": "slack", "accountId": "<agent-id>" } }
  ]
}
```

### 6. Reload & Approve

```bash
# Reload config
kill -HUP 1   # in container
# or: openclaw gateway restart

# Verify
openclaw channels status --probe

# Approve first DM
openclaw pairing approve slack <CODE>
```

## GitHub Setup

### Per-Agent Git Identity

Each agent gets unique git credentials for commit attribution:

```bash
# Generate SSH key
mkdir -p ~/.openclaw/agents/<agent-id>/ssh
ssh-keygen -t ed25519 -C "<agent-id>@damesoftware.com" \
  -f ~/.openclaw/agents/<agent-id>/ssh/id_ed25519 -N ""

# Configure git identity in workspace
git -C ~/.openclaw/workspace-<agent-id> config user.name "<Name> (<agent-id>)"
git -C ~/.openclaw/workspace-<agent-id> config user.email "<agent-id>@damesoftware.com"
```

### HTTPS Access (All Repos)

For access to all org repos, use a GitHub PAT with credential store:

```bash
echo "https://x-access-token:<PAT>@github.com" > ~/.openclaw/agents/<agent-id>/.git-credentials
git -C ~/.openclaw/workspace-<agent-id> config credential.helper \
  "store --file=$HOME/.openclaw/agents/<agent-id>/.git-credentials"
```

### Deploy Keys (Per-Repo)

For scoped access, add SSH public keys as deploy keys via GitHub API:

```bash
curl -X POST -H "Authorization: token <PAT>" \
  https://api.github.com/repos/<org>/<repo>/keys \
  -d "{\"title\": \"<agent-id>\", \"key\": \"$(cat ~/.openclaw/agents/<agent-id>/ssh/id_ed25519.pub)\", \"read_only\": false}"
```

## Troubleshooting

### Agent not responding to DMs
1. Check pairing: `openclaw pairing list slack`
2. Check routing: `openclaw agents list --bindings`
3. Check probe: `openclaw channels status --probe`

### Agent responding with wrong identity
1. Session has cached old persona. Reset it:
   - Send `/reset` in the agent's DM, OR
   - Delete session files: `rm ~/.openclaw/agents/<agent-id>/sessions/*`

### Socket not connecting
1. Verify `appToken` has `connections:write` scope
2. Check logs: `openclaw logs --follow`

### Slack app limit reached
- Free workspaces have limited app slots
- Delete unused apps: `curl -X POST https://slack.com/api/apps.manifest.delete -H "Authorization: Bearer $CONFIG_TOKEN" -d '{"app_id": "A0..."}'`
- Or upgrade workspace plan

## Slack Free Tier Limits

- ~10 apps per workspace (varies)
- If you hit the limit, options:
  1. Delete old/unused apps via API
  2. Share one bot for multiple agents (use `chat:write.customize` for display names)
  3. Upgrade workspace

## Config Reference

Full `openclaw.json` example for multi-agent:

```json5
{
  "agents": {
    "list": [
      { "id": "main", "identity": { "name": "Claw", "emoji": "🦞" } },
      {
        "id": "siteconfig",
        "workspace": "~/.openclaw/workspace-siteconfig",
        "agentDir": "~/.openclaw/agents/siteconfig/agent",
        "identity": { "name": "Sanjay", "emoji": "🔧" }
      }
    ]
  },
  "bindings": [
    { "agentId": "siteconfig", "match": { "channel": "slack", "accountId": "siteconfig" } },
    { "agentId": "main", "match": { "channel": "slack", "accountId": "default" } }
  ],
  "channels": {
    "slack": {
      "mode": "socket",
      "enabled": true,
      "groupPolicy": "open",
      "streaming": "partial",
      "nativeStreaming": true,
      "accounts": {
        "default": { "botToken": "xoxb-...", "appToken": "xapp-..." },
        "siteconfig": { "botToken": "xoxb-...", "appToken": "xapp-..." }
      }
    }
  }
}
```
