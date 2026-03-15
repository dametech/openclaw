# Slack Integration Setup Guide

This guide covers setting up Slack integration for OpenClaw using the automated setup script.

## Prerequisites

- Running OpenClaw deployment in Kubernetes
- Slack workspace admin access
- 1Password CLI (optional but recommended)
- kubectl and helm installed

## Quick Setup

```bash
./setup-slack-integration.sh
```

The script will guide you through:
1. Creating a Slack app (manual steps in Slack UI)
2. Collecting App and Bot tokens
3. Storing tokens securely (1Password or Kubernetes secrets)
4. Updating OpenClaw configuration
5. Deploying to Kubernetes
6. Testing the integration

## Manual Setup Steps (In Slack)

### 1. Create Slack App

1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. App Name: `OpenClaw Bot` (or your choice)
4. Select your workspace

### 2. Enable Socket Mode

1. Navigate to "Socket Mode" in sidebar
2. Toggle "Enable Socket Mode" to ON
3. Click "Generate" to create App-Level Token
4. Token Name: `openclaw-socket`
5. Add scope: `connections:write`
6. **Copy the App Token (xapp-...)**

### 3. Configure OAuth Scopes

Navigate to "OAuth & Permissions" → "Bot Token Scopes" and add:

**Essential Scopes:**
- `chat:write` - Send messages
- `chat:write.customize` - Custom bot identity (optional)
- `channels:history` - Read public channel history
- `channels:read` - Access channel metadata
- `groups:history` - Read private channel history
- `im:history` - Read DM history
- `im:read` - Access DM metadata
- `mpim:history` - Read group DM history
- `mpim:read` - Access group DM metadata
- `app_mentions:read` - Receive @mentions
- `reactions:read` - View emoji reactions
- `reactions:write` - Add emoji reactions
- `pins:read` - View pinned messages
- `pins:write` - Pin messages
- `emoji:read` - Access workspace emoji
- `commands` - Support slash commands
- `files:read` - Access uploaded files
- `files:write` - Upload files

### 4. Install App to Workspace

1. Scroll to top of "OAuth & Permissions"
2. Click "Install to Workspace"
3. Authorize the app
4. **Copy the Bot User OAuth Token (xoxb-...)**

### 5. Subscribe to Bot Events

Navigate to "Event Subscriptions":

1. Toggle "Enable Events" to ON
2. Under "Subscribe to bot events", add:
   - `app_mention`
   - `message.channels`
   - `message.groups`
   - `message.im`
   - `message.mpim`
   - `reaction_added`
   - `reaction_removed`
   - `member_joined_channel`
   - `member_left_channel`
   - `channel_rename`
   - `pin_added`
   - `pin_removed`
3. Click "Save Changes"

### 6. Enable App Home

1. Navigate to "App Home"
2. Under "Show Tabs", enable "Messages Tab"
3. Check "Allow users to send Slash commands and messages from the messages tab"

## Configuration

### OpenClaw Configuration (openclaw.json)

The automated script generates this configuration:

```json5
{
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "appToken": "${SLACK_APP_TOKEN}",
      "botToken": "${SLACK_BOT_TOKEN}",
      "userAuth": {
        "mode": "allowlist"  // Only approved users can interact
      }
    }
  }
}
```

### User Authorization Modes

**Allowlist Mode (Recommended):**
```json5
"userAuth": {
  "mode": "allowlist",
  "allowlist": ["U01234ABCD", "U56789EFGH"]  // Slack user IDs
}
```

**Open Mode (Allow All):**
```json5
"userAuth": {
  "mode": "open"
}
```

**Disabled Mode (Reject All):**
```json5
"userAuth": {
  "mode": "disabled"
}
```

## Token Storage

### Using 1Password (Recommended)

Tokens are stored in 1Password vault as:
```
op:///openclaw/OpenClaw Slack Tokens/app_token
op:///openclaw/OpenClaw Slack Tokens/bot_token
```

### Using Kubernetes Secrets Only

Tokens are stored in:
```
namespace: openclaw
secret: openclaw-slack-tokens
  SLACK_APP_TOKEN: xapp-...
  SLACK_BOT_TOKEN: xoxb-...
```

## Testing the Integration

### 1. Check Pod Logs

```bash
export KUBECONFIG=~/.kube/au01-0.yaml
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main -f
```

Look for:
```
[slack] Socket Mode connection established
[slack] Connected to workspace: YourWorkspace
```

### 2. Send Test Message

1. Open Slack
2. Find OpenClaw bot in Apps section
3. Send a DM: "Hello!"

### 3. Approve Pairing (If Needed)

If you see a pairing request in logs:

```bash
# List pairing requests
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing list

# Approve pairing
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing approve slack <code>
```

### 4. Invite to Channel

In any Slack channel:
```
/invite @OpenClaw
```

Then mention the bot:
```
@OpenClaw what can you help me with?
```

## Troubleshooting

### Bot Not Responding

**Check Socket Mode Connection:**
```bash
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main | grep -i slack
```

**Verify Tokens:**
```bash
kubectl get secret openclaw-slack-tokens -n openclaw -o yaml
```

**Check Pairing Status:**
```bash
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing list
```

### "App Token Invalid" Error

- Regenerate App Token in Slack app settings
- Ensure it has `connections:write` scope
- Update Kubernetes secret with new token
- Restart pod: `kubectl rollout restart deployment/openclaw -n openclaw`

### "Bot Token Invalid" Error

- Bot might not be installed to workspace
- Reinstall app from "OAuth & Permissions"
- Copy new Bot Token
- Update Kubernetes secret

### Socket Mode Connection Fails

- Check if Socket Mode is enabled in Slack app settings
- Verify App Token is valid and has correct scope
- Check pod network connectivity
- Review firewall rules (outbound WebSocket connections to Slack)

### User Not Approved

If using allowlist mode, add user to allowlist:

```json5
"userAuth": {
  "mode": "allowlist",
  "allowlist": ["U01234ABCD"]  // Add Slack user ID
}
```

Or approve via pairing:
```bash
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing approve slack <code>
```

## Advanced Configuration

### Custom Bot Identity

Enable `chat:write.customize` scope and configure:

```json5
{
  "agents": {
    "list": [
      {
        "id": "main",
        "identity": {
          "name": "OpenClaw Assistant",
          "emoji": "🦞"
        }
      }
    ]
  }
}
```

### Multi-Workspace Deployment

Create separate Slack apps for each workspace and configure multiple accounts:

```json5
{
  "channels": {
    "slack": {
      "enabled": true,
      "accounts": {
        "workspace1": {
          "mode": "socket",
          "appToken": "${SLACK_APP_TOKEN_1}",
          "botToken": "${SLACK_BOT_TOKEN_1}"
        },
        "workspace2": {
          "mode": "socket",
          "appToken": "${SLACK_APP_TOKEN_2}",
          "botToken": "${SLACK_BOT_TOKEN_2}"
        }
      }
    }
  }
}
```

### Slash Commands

To add custom slash commands:

1. In Slack app settings, go to "Slash Commands"
2. Create new command (e.g., `/openclaw`)
3. For Socket Mode, no Request URL needed
4. Configure in openclaw.json:

```json5
{
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "commands": {
        "/openclaw": {
          "description": "Interact with OpenClaw",
          "usage_hint": "[your message]"
        }
      }
    }
  }
}
```

### Scheduled Messages

Use cron syntax to schedule messages:

```json5
{
  "channels": {
    "slack": {
      "enabled": true,
      "scheduled": [
        {
          "cron": "0 9 * * 1-5",  // Weekdays at 9 AM
          "channel": "C01234ABCD",
          "message": "Good morning! How can I help today?"
        }
      ]
    }
  }
}
```

## Security Best Practices

1. **Use Allowlist Mode**: Start with restricted access
2. **Store Tokens in 1Password**: Never commit tokens to git
3. **Rotate Tokens Regularly**: Update tokens every 90 days
4. **Monitor Access Logs**: Review who is using the bot
5. **Limit Bot Permissions**: Only grant necessary OAuth scopes
6. **Use Service Accounts**: For production deployments

## Updating Configuration

To update Slack configuration without downtime:

```bash
# Edit configuration
kubectl edit configmap openclaw -n openclaw

# Reload configuration (if supported)
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js secrets reload

# Or restart pod
kubectl rollout restart deployment/openclaw -n openclaw
```

## Cleanup

To remove Slack integration:

```bash
# Remove from openclaw.json (set enabled: false)
kubectl edit configmap openclaw -n openclaw

# Restart deployment
kubectl rollout restart deployment/openclaw -n openclaw

# Optionally delete tokens
kubectl delete secret openclaw-slack-tokens -n openclaw

# Uninstall Slack app from workspace (in Slack app settings)
```

## References

- [Official OpenClaw Slack Documentation](https://docs.openclaw.ai/channels/slack)
- [Slack API Documentation](https://api.slack.com/apis)
- [Socket Mode Guide](https://api.slack.com/apis/connections/socket)
- [OAuth Scopes Reference](https://api.slack.com/scopes)

---

**Last Updated**: March 2026
**OpenClaw Version**: 2026.3.13+
