# Jira Setup

How Jira access is configured for OpenClaw agents. All agents share a single API token (via a human account) for simplicity. Per-agent Jira accounts can be added later if attribution granularity is needed.

## Architecture

```
Jira Cloud (Atlassian)
│
├── Basic auth: email + API token
│
├── Credentials: ~/.openclaw/credentials/jira.json
│
├── Wrapper script: ~/.openclaw/bin/jira-api.sh
│
└── All agents → shared access
```

## Prerequisites

- Jira Cloud instance (Atlassian)
- An account with appropriate project access
- An API token for that account

## Setup Steps

### 1. Generate a Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click **Create API token**
3. Name it (e.g. `openclaw-agents`)
4. Set expiry (max 1 year — set a reminder to rotate)
5. Copy the token

> **Note:** Atlassian enforces token expiry. Tokens created after Dec 2024 expire within 1 year max. Set a calendar reminder to rotate before expiry.

### 2. Store Credentials

```bash
mkdir -p ~/.openclaw/credentials

cat > ~/.openclaw/credentials/jira.json << 'EOF'
{
  "url": "https://<your-instance>.atlassian.net",
  "email": "<your-email>",
  "token": "<your-api-token>"
}
EOF

chmod 600 ~/.openclaw/credentials/jira.json
```

### 3. Create the Wrapper Script

```bash
mkdir -p ~/.openclaw/bin

cat > ~/.openclaw/bin/jira-api.sh << 'SCRIPT'
#!/bin/sh
# jira-api.sh — Simple Jira API wrapper
# Usage: jira-api.sh <METHOD> <path> [json-body]
#
# Examples:
#   jira-api.sh GET /rest/api/3/myself
#   jira-api.sh GET "/rest/api/3/search?jql=project=VOLT"
#   jira-api.sh POST /rest/api/3/issue '{"fields":{...}}'

CREDS_FILE="$HOME/.openclaw/credentials/jira.json"
JIRA_URL=$(python3 -c "import json; print(json.load(open('$CREDS_FILE'))['url'])")
JIRA_EMAIL=$(python3 -c "import json; print(json.load(open('$CREDS_FILE'))['email'])")
JIRA_TOKEN=$(python3 -c "import json; print(json.load(open('$CREDS_FILE'))['token'])")

METHOD="${1:?Usage: $0 <METHOD> <path> [body]}"
API_PATH="${2:?Missing API path}"
BODY="${3:-}"

if [ -n "$BODY" ]; then
  curl -s -X "$METHOD" -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${JIRA_URL}${API_PATH}" -d "$BODY"
else
  curl -s -X "$METHOD" -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${JIRA_URL}${API_PATH}"
fi
SCRIPT

chmod +x ~/.openclaw/bin/jira-api.sh
```

### 4. Verify

```bash
# Test authentication
~/.openclaw/bin/jira-api.sh GET /rest/api/3/myself

# List projects
~/.openclaw/bin/jira-api.sh GET /rest/api/3/project
```

## Usage Examples

### Search issues
```bash
# All open issues in a project
jira-api.sh GET "/rest/api/3/search?jql=project=VOLT+AND+status!=Done&maxResults=20"

# Issues assigned to someone
jira-api.sh GET "/rest/api/3/search?jql=assignee=currentUser()+ORDER+BY+updated+DESC"
```

### Create an issue
```bash
jira-api.sh POST /rest/api/3/issue '{
  "fields": {
    "project": { "key": "VOLT" },
    "summary": "Implement hashrate anomaly detection",
    "description": { "type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Details here"}]}] },
    "issuetype": { "name": "Task" }
  }
}'
```

### Update an issue
```bash
# Transition (move status)
jira-api.sh POST /rest/api/3/issue/VOLT-123/transitions '{"transition": {"id": "31"}}'

# Add comment
jira-api.sh POST /rest/api/3/issue/VOLT-123/comment '{
  "body": { "type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Work completed."}]}] }
}'
```

## Automation Potential

### What can be automated

- **Credential storage** — fully scriptable (steps 2-3 above)
- **Wrapper script creation** — fully scriptable
- **Verification** — fully scriptable
- **Project discovery** — `GET /rest/api/3/project` lists all accessible projects
- **Issue creation/updates** — full REST API available

### What requires manual steps

- **API token generation** — must be done in the Atlassian UI (no API to create API tokens)
- **Token rotation** — manual generation, then update `jira.json`
- **Permission grants** — project access is managed in Jira admin UI

### Automation via OAuth 2.0 (future)

For true per-agent Jira access without sharing a personal token, Atlassian supports OAuth 2.0 (3LO):
- Register an OAuth app at https://developer.atlassian.com/console/myapps/
- Each agent could authenticate with its own OAuth token
- Grants can be scoped per app
- Requires initial consent flow (browser-based)

This is more complex but provides better audit trails and permission isolation.

### Scoped API Tokens (available now)

Atlassian now supports **scoped API tokens** with granular permissions:
- Read/write scopes for Jira and Confluence
- Can create tokens with minimal permissions per use case
- Still tied to a human account

## Adding to the Provisioning Script

The `scripts/create-agent.sh` does not currently set up Jira access because it's a one-time global setup (not per-agent). To include in provisioning:

```bash
# In your provisioning flow, after credential store exists:
~/.openclaw/bin/jira-api.sh GET /rest/api/3/myself > /dev/null && echo "Jira: OK" || echo "Jira: FAILED"
```

## Security Notes

- Credentials stored in `~/.openclaw/credentials/jira.json` with `600` permissions
- All agents share one token — actions appear as the token owner in Jira
- **Do not commit the token to any repository**
- API tokens expire (max 1 year) — set a rotation reminder
- To rotate: update `jira.json` with the new token — all agents pick it up immediately

## TODO

- [ ] Per-agent Jira accounts or OAuth 2.0 app for granular attribution
- [ ] Token rotation reminder/alerting (cron job or heartbeat check)
- [ ] Integrate Jira wrapper into the team definition provisioning script
- [ ] Consider an OpenClaw skill for Jira (structured tool instead of raw API calls)
