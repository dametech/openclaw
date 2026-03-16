# Slack Integration - Working Setup Process

**Last Tested**: March 16, 2026
**Status**: ✅ WORKING
**OpenClaw Version**: 2026.3.13-1

This document captures the **actual working process** for setting up Slack integration based on successful deployment.

## Critical Lessons Learned

### 1. **Scope Requirements**
The bot token needs **WRITE scopes**, not just read scopes:
- ✅ `chat:write` - Send messages
- ✅ `chat:write.public` - Send to public channels bot isn't in
- ✅ `im:write` - Send DMs
- ✅ `channels:join` - Join channels
- ✅ `groups:write` - Send to private channels

**Common mistake**: Adding only read scopes (`channels:history`, `im:history`) allows receiving but not sending messages.

### 2. **Reinstall After Every Scope Change**
- Adding/removing scopes requires **reinstalling the app**
- Each reinstall generates a **NEW token**
- The new token is what has the updated scopes
- Old tokens become invalid or lack the new scopes

### 3. **Event Subscriptions Must Be Saved**
- Adding events without clicking "Save Changes" = events don't work
- After saving events, Slack shows "Please reinstall your app"
- You MUST reinstall for events to activate

### 4. **Two-Phase Setup is Required**
- Phase 1: Create app, add Socket Mode, add scopes, install (get initial tokens)
- Phase 2: Add event subscriptions, save, REINSTALL (get new token with events)

## Working Setup Process

### Phase 1: Initial App Creation

#### Step 1: Create Slack App
1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. App Name: `claw` (or your choice)
4. Select workspace
5. Click "Create App"

#### Step 2: Enable Socket Mode FIRST
1. In sidebar → "Socket Mode"
2. Toggle "Enable Socket Mode" to ON
3. Click "Generate"
4. Token Name: `openclaw-socket`
5. Add scope: `connections:write`
6. Click "Generate"
7. **COPY App Token (xapp-...)** and save it

#### Step 3: Add OAuth Scopes
1. In sidebar → "OAuth & Permissions"
2. Scroll to "Bot Token Scopes"
3. Add ALL these scopes (especially the write ones):

**Essential Write Scopes** (without these, bot can't reply):
```
chat:write
chat:write.public
chat:write.customize
im:write
groups:write
```

**Read Scopes** (for receiving messages):
```
channels:history
channels:read
channels:join
groups:history
im:history
im:read
mpim:history
mpim:read
app_mentions:read
```

**Additional Scopes**:
```
reactions:read
reactions:write
pins:read
pins:write
emoji:read
commands
files:read
files:write
```

#### Step 4: Install App (First Time)
1. Scroll to top of "OAuth & Permissions"
2. Click "Install to Workspace"
3. Authorize
4. **COPY Bot Token (xoxb-...)** and save it

**Note**: This token will be replaced in Phase 2!

### Phase 2: Add Events and Reinstall

#### Step 5: Add Event Subscriptions
1. In sidebar → "Event Subscriptions"
2. Toggle "Enable Events" to ON
3. You should see: "Socket mode is enabled. You don't need a request URL."
4. Scroll to "Subscribe to bot events"
5. Click "Add Bot User Event" and add:

**Required Events**:
```
app_mention
message.channels
message.groups
message.im
message.mpim
reaction_added
reaction_removed
member_joined_channel
member_left_channel
channel_rename
pin_added
pin_removed
```

6. **Click "Save Changes"** at bottom
7. Yellow banner appears: "Please reinstall your app"

#### Step 6: Enable Messages Tab (Optional)
1. In sidebar → "App Home"
2. Under "Show Tabs", toggle "Messages Tab" to ON
3. Enable "Allow users to send Slash commands and messages"

#### Step 7: Reinstall App (CRITICAL!)
1. In sidebar → "OAuth & Permissions"
2. Click "Reinstall to Workspace"
3. Authorize
4. **COPY THE NEW Bot Token (xoxb-...)**
   ⚠️ This is a DIFFERENT token than Step 4!
   ⚠️ This new token has the event subscriptions activated!

### Phase 3: Deploy to Kubernetes

#### Step 8: Update Pod Configuration

```bash
# Get current config from pod
export KUBECONFIG=~/.kube/au01-0.yaml
kubectl exec -n openclaw deployment/openclaw -c main -- \
  cat /home/node/.openclaw/openclaw.json > /tmp/openclaw-current.json

# Update tokens with jq
cat /tmp/openclaw-current.json | \
  jq '.channels.slack.appToken = "xapp-YOUR-APP-TOKEN"' | \
  jq '.channels.slack.botToken = "xoxb-YOUR-BOT-TOKEN"' | \
  jq '.channels.slack.enabled = true' | \
  jq '.channels.slack.mode = "socket"' \
  > /tmp/openclaw-updated.json

# Write back to pod
kubectl exec -n openclaw deployment/openclaw -c main -i -- \
  sh -c 'cat > /home/node/.openclaw/openclaw.json' < /tmp/openclaw-updated.json

# Restart pod
kubectl rollout restart deployment/openclaw -n openclaw

# Wait for ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=openclaw \
  -n openclaw \
  --timeout=120s
```

#### Step 9: Approve Pairing

After restarting, send a message to the bot in Slack.

Check for pairing requests:
```bash
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing list slack
```

Approve pairing:
```bash
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing approve slack <CODE>
```

#### Step 10: Test

Send another message to the bot - it should respond!

## Configuration Reference

### Minimal Working openclaw.json Slack Config

```json
{
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "appToken": "xapp-1-AXXXXXXXXX-...",
      "botToken": "xoxb-XXXXXXXXX-XXXXXXXXX-XXXXXXXXXXXXXXXX"
    }
  }
}
```

### Full Slack Config (with optional settings)

```json
{
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "webhookPath": "/slack/events",
      "appToken": "xapp-1-AXXXXXXXXX-...",
      "botToken": "xoxb-XXXXXXXXX-XXXXXXXXX-XXXXXXXXXXXXXXXX",
      "userTokenReadOnly": true,
      "groupPolicy": "allowlist",
      "streaming": "partial",
      "nativeStreaming": true
    }
  }
}
```

## Troubleshooting

### Error: `missing_scope`

**Cause**: Bot token doesn't have required write scopes

**Solution**:
1. Add missing write scopes (`chat:write`, `im:write`, `chat:write.public`)
2. **Reinstall app** to get new token with scopes
3. Update token in pod configuration
4. Restart pod

### Error: `account_inactive`

**Cause**: Token was revoked or app isn't properly installed

**Solution**:
1. Go to OAuth & Permissions
2. Verify "App is installed to your workspace"
3. If not, click "Install to Workspace"
4. If already installed, click "Reinstall to Workspace"
5. Get new token and update pod

### Bot Receives Messages But Doesn't Reply

**Symptoms**: Logs show `[slack] socket mode connected` but `[slack] final reply failed`

**Cause**: Missing write scopes

**Solution**: Add all write scopes listed above, reinstall, update token

### No Events Received

**Symptoms**: `[slack] socket mode connected` but no message events in logs

**Cause**: Event subscriptions not saved or app not reinstalled after adding events

**Solution**:
1. Verify events are listed in Event Subscriptions page
2. Ensure you clicked "Save Changes"
3. Reinstall the app
4. Update token in pod

## Automated Update Script

Create a script to update Slack tokens without full redeploy:

```bash
#!/bin/bash
# update-slack-token.sh

export KUBECONFIG=~/.kube/au01-0.yaml
NAMESPACE="openclaw"

APP_TOKEN="$1"
BOT_TOKEN="$2"

if [ -z "$APP_TOKEN" ] || [ -z "$BOT_TOKEN" ]; then
    echo "Usage: $0 <app-token> <bot-token>"
    exit 1
fi

# Get current config
kubectl exec -n $NAMESPACE deployment/openclaw -c main -- \
  cat /home/node/.openclaw/openclaw.json > /tmp/openclaw-current.json

# Update tokens
cat /tmp/openclaw-current.json | \
  jq ".channels.slack.appToken = \"$APP_TOKEN\"" | \
  jq ".channels.slack.botToken = \"$BOT_TOKEN\"" \
  > /tmp/openclaw-updated.json

# Write back
kubectl exec -n $NAMESPACE deployment/openclaw -c main -i -- \
  sh -c 'cat > /home/node/.openclaw/openclaw.json' < /tmp/openclaw-updated.json

# Restart
kubectl rollout restart deployment/openclaw -n $NAMESPACE
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=openclaw -n $NAMESPACE --timeout=120s

echo "✓ Tokens updated and pod restarted"
```

## Token Management Best Practices

1. **Save tokens in 1Password** when you generate them
2. **Document which token is current** (tokens change with each reinstall)
3. **Test immediately after reinstall** to verify scopes work
4. **Keep a log** of when you reinstalled and why
5. **Rotate tokens regularly** (every 90 days)

## Verification Checklist

Before declaring Slack integration "working", verify:

- [ ] Socket Mode enabled and app token generated
- [ ] All write scopes added (`chat:write`, `im:write`, `chat:write.public`, etc.)
- [ ] All read scopes added (18 total scopes minimum)
- [ ] App installed to workspace
- [ ] Event subscriptions added (12 events minimum)
- [ ] Event subscriptions SAVED
- [ ] App REINSTALLED after adding events
- [ ] New bot token copied (from reinstall)
- [ ] Token updated in pod configuration
- [ ] Pod restarted
- [ ] `[slack] socket mode connected` appears in logs
- [ ] Pairing approved for your user
- [ ] Bot responds to messages (no `missing_scope` errors)

## Success Indicators

When working correctly, logs show:
```
[slack] socket mode connected
[slack] received event: app_mention
[slack] processing message from user U08N2P6BA9K
[slack] sending response
```

No errors about `missing_scope` or `account_inactive`.

---

**Working Setup Confirmed**: March 16, 2026
**User ID**: U08N2P6BA9K
**Bot Name**: @claw
**Workspace**: (your workspace)
