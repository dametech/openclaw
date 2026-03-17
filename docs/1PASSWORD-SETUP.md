# 1Password Integration for OpenClaw Agents

## Overview

Use 1Password Service Accounts to securely provide credentials to OpenClaw agents without storing secrets in plaintext on the PVC or passing them through Slack.

## Architecture

```
1Password Cloud (your vault)
    │
    │  OP_SERVICE_ACCOUNT_TOKEN (K8s Secret)
    │
    ▼
OpenClaw Container
    ├── op read "op://Vault/Item/field"     ← on-demand secret fetch
    ├── op inject < template.env             ← bulk env injection
    └── op run -- ./my-script.sh             ← run with secrets in env
```

**Key principles:**
- Secrets are fetched on-demand from 1Password, not stored on disk
- Service account token is the only secret stored (in K8s Secret, injected as env var)
- Agents use `op read` / `op run` to access secrets at runtime
- Vault access is scoped — service account only sees what you allow

## Setup Steps

### Step 1: Create a 1Password Vault (Andrew)

Create a dedicated vault for agent secrets. Don't use Personal/Shared vaults (1Password doesn't allow service account access to those).

**Suggested vault name:** `OpenClaw-Agents`

**Items to store:**
| Item Name | Fields | Purpose |
|-----------|--------|---------|
| `AWS-Backup` | `access-key-id`, `secret-access-key`, `region` | S3 backup credentials |
| `AWS-Main` | `access-key-id`, `secret-access-key`, `region` | AWS operations (Lambdas, etc.) |
| `GitHub-PAT` | `token` | GitHub API access |
| `Slack-Tokens` | `default-bot`, `default-app`, `davo-bot`, `davo-app`, etc. | Slack integration |
| `Anthropic` | `api-key` | LLM API key |
| `Jira` | `email`, `api-token`, `base-url` | Jira integration |
| `Gateway` | `token` | OpenClaw gateway auth |

### Step 2: Create a Service Account (Andrew)

1. Sign in to [1Password.com](https://start.1password.com/signin)
2. Go to **Developer** → **Directory** → **Other** → **Create a Service Account**
3. Name it: `openclaw-au01` (or similar)
4. Grant **read-only** access to the `OpenClaw-Agents` vault
5. **Save the service account token immediately** — it's only shown once
6. Token looks like: `ops_...`

### Step 3: Store Token in Kubernetes (Andrew or Davo)

```bash
export KUBECONFIG=~/.kube/au01-0.yaml

kubectl create secret generic openclaw-1password \
  --namespace openclaw \
  --from-literal=OP_SERVICE_ACCOUNT_TOKEN='ops_YOUR_TOKEN_HERE'
```

### Step 4: Add to Helm Values

Update the Helm deployment to inject the token:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          envFrom:
            - secretRef:
                name: openclaw-env-secret      # existing (ANTHROPIC_API_KEY)
            - secretRef:
                name: openclaw-1password       # new (OP_SERVICE_ACCOUNT_TOKEN)
```

### Step 5: Verify (Davo)

After pod restart with the new env var:

```bash
# Test service account auth
op whoami

# Read a secret
op read "op://OpenClaw-Agents/AWS-Backup/access-key-id"

# List vault contents
op item list --vault "OpenClaw-Agents"
```

## Usage Patterns

### Read a single secret
```bash
AWS_KEY=$(op read "op://OpenClaw-Agents/AWS-Backup/access-key-id")
```

### Inject secrets into a command
```bash
# template.env:
# AWS_ACCESS_KEY_ID={{ op://OpenClaw-Agents/AWS-Backup/access-key-id }}
# AWS_SECRET_ACCESS_KEY={{ op://OpenClaw-Agents/AWS-Backup/secret-access-key }}

op inject -i template.env -o .env
```

### Run a command with secrets in environment
```bash
op run --env-file=template.env -- python3 backup-s3.py
```

### Secret reference format
```
op://<vault>/<item>/<field>
```

Examples:
```
op://OpenClaw-Agents/AWS-Backup/access-key-id
op://OpenClaw-Agents/GitHub-PAT/token
op://OpenClaw-Agents/Jira/api-token
```

## Migration Plan

Once 1Password is working:

1. **AWS creds** → move from `~/.openclaw/credentials/aws-backup.json` to `op read`
2. **GitHub PAT** → move from `~/.git-credentials` to `op read` + git credential helper
3. **Slack tokens** → move from `openclaw.json` to K8s Secret populated by `op inject`
4. **Jira creds** → move from `~/.openclaw/credentials/jira.json` to `op read`
5. **Anthropic key** → already in K8s Secret, optionally move source-of-truth to 1Password
6. **Rotate all credentials** that were ever in plaintext

## Rate Limits

Service accounts have hourly and daily request limits:
- Use vault/item **IDs** instead of names to reduce API calls (3 reads → 1 read)
- Cache secrets in memory for the duration of a script/session
- Don't call `op read` in tight loops

## Security Notes

- Service account token (`ops_...`) is the crown jewel — protect it like any other secret
- Grant **read-only** access unless agents need to write to the vault
- One vault per environment (don't mix prod/dev secrets)
- Audit service account usage in 1Password's activity log
- Rotate the service account token periodically (requires creating a new service account)

## Requirements

- 1Password Business or Teams plan (service accounts not available on individual plans)
- `op` CLI v2.18.0+ (installed: v2.30.3 at `~/.openclaw/bin/op`)
- `OP_SERVICE_ACCOUNT_TOKEN` env var set in the container
