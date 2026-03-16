# GitHub Access Setup

How GitHub access is configured for OpenClaw agents, providing per-agent commit attribution across all repositories.

## Architecture

```
GitHub (org + user repos)
│
├── HTTPS + PAT authentication (shared token)
│
├── Global credential store (~/.openclaw/.git-credentials)
│   └── XDG_CONFIG_HOME=~/.openclaw → git/config
│
└── Per-agent git identity (workspace-level .git/config)
    └── <agent-id>@<domain>
```

## How It Works

### Authentication

All agents share a single GitHub Personal Access Token (PAT) stored in a central credentials file. This grants read/write access to all repos the token has access to.

**Credential file:** `~/.openclaw/.git-credentials`

```
https://x-access-token:<PAT>@github.com
```

**Git config:** `~/.openclaw/git/config`

```ini
[credential]
    helper = store --file=/home/node/.openclaw/.git-credentials
```

### Environment

Because the container runs with a read-only root filesystem, `~/.gitconfig` is not writable. Instead, git's XDG config lookup is used:

```
XDG_CONFIG_HOME=/home/node/.openclaw
```

This makes git read `~/.openclaw/git/config` as the global config, which points to the credential store. The `XDG_CONFIG_HOME` env var is set in the OpenClaw gateway config (`env` section in `openclaw.json`).

### Per-Agent Identity

Each agent's workspace has its own `.git/config` with a unique identity:

```ini
[user]
    name = <Name> (<agent-id>)
    email = <agent-id>@<domain>
[credential]
    helper = store --file=/home/node/.openclaw/.git-credentials
```

This means:
- **Authentication** is shared (one PAT, all repos)
- **Attribution** is unique (each agent's commits show their name/email)

## Setup Steps

### 1. Create the global credential store

```bash
# Create git config directory (XDG path)
mkdir -p ~/.openclaw/git

# Store the PAT
echo "https://x-access-token:<YOUR_PAT>@github.com" > ~/.openclaw/.git-credentials
chmod 600 ~/.openclaw/.git-credentials

# Create global git config
cat > ~/.openclaw/git/config << 'EOF'
[credential]
    helper = store --file=/home/node/.openclaw/.git-credentials
EOF
```

### 2. Set XDG_CONFIG_HOME in OpenClaw config

Add to `openclaw.json`:

```json5
{
  "env": {
    "XDG_CONFIG_HOME": "/home/node/.openclaw"
  }
}
```

### 3. Configure per-agent git identity

For each agent workspace:

```bash
AGENT_ID="myagent"
DISPLAY_NAME="AgentName"
DOMAIN="example.com"
WORKSPACE="$HOME/.openclaw/workspace-${AGENT_ID}"

git -C "$WORKSPACE" config user.name "${DISPLAY_NAME} (${AGENT_ID})"
git -C "$WORKSPACE" config user.email "${AGENT_ID}@${DOMAIN}"
git -C "$WORKSPACE" config credential.helper "store --file=/home/node/.openclaw/.git-credentials"
```

### 4. Verify

```bash
# Test clone from any directory
git clone https://github.com/<org>/<repo>.git /tmp/test-clone
rm -rf /tmp/test-clone

# Verify identity in a workspace
git -C ~/.openclaw/workspace-<agent-id> config user.name
git -C ~/.openclaw/workspace-<agent-id> config user.email
```

## Automation

The `scripts/create-agent.sh` script handles git identity setup automatically when creating a new agent. The credential store must be set up once (steps 1-2 above).

## Security Notes

- The PAT is stored in `~/.openclaw/.git-credentials` with `600` permissions
- All agents share the same PAT — this is intentional for simplicity
- The PAT should have `repo` scope (for private repos) and `read:org` (for org repo listing)
- **Do not commit the PAT to any repository**
- To rotate: update `~/.openclaw/.git-credentials` with the new token — all agents pick it up immediately
- For stricter isolation, use per-agent deploy keys instead (see `docs/MULTI-AGENT-SETUP.md`)

## Troubleshooting

### "could not read Username" on clone

Git can't find credentials. Check:
1. `~/.openclaw/.git-credentials` exists and contains the PAT
2. `XDG_CONFIG_HOME` is set to `/home/node/.openclaw`
3. `~/.openclaw/git/config` exists with the credential helper

### Commits showing wrong author

Check workspace-level git config:
```bash
git -C ~/.openclaw/workspace-<agent-id> config user.name
git -C ~/.openclaw/workspace-<agent-id> config user.email
```

### Clone works in workspace but not /tmp

The workspace-level credential helper only applies inside the workspace. Ensure either:
- `XDG_CONFIG_HOME` is set (recommended), or
- `GIT_CONFIG_GLOBAL` points to a writable gitconfig with the credential helper
