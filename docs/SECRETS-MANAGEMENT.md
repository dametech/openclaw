# Secrets Management

## Current State

Secrets are stored as plaintext files in `~/.openclaw/` with `600` permissions:

| Secret | Location | Shared by |
|--------|----------|-----------|
| GitHub PAT | `~/.openclaw/.git-credentials` | All agents |
| Jira API token | `~/.openclaw/credentials/jira.json` | All agents |
| Slack bot tokens | `~/.openclaw/openclaw.json` | Per-agent |
| Slack app tokens | `~/.openclaw/openclaw.json` | Per-agent |
| Anthropic API key | Environment variable | All agents |
| Gateway auth token | `~/.openclaw/openclaw.json` | Gateway |

**Problems with current approach:**
- Secrets in plaintext files on the PVC
- No rotation automation
- No audit trail for secret access
- No expiry alerting
- Credentials shared in `openclaw.json` alongside non-secret config

## TODO

- [ ] Evaluate and select a secrets management solution
- [ ] Migrate existing secrets to the chosen solution
- [ ] Set up rotation automation where possible
- [ ] Add expiry monitoring/alerting (Jira tokens expire within 1 year)
- [ ] Document the migration process

## Options Evaluated

### 1. 1Password (Recommended for evaluation)

**Approach:** 1Password Service Accounts + CLI (`op`)

**Pros:**
- Service Accounts don't require a human login — ideal for containers
- Up to 100 service accounts per org
- Vault-scoped access — can isolate secrets per agent or per service
- `op run` injects secrets as env vars (no files on disk)
- `op read` fetches individual secrets on demand
- Audit log for all secret access
- Browser extension + CLI for human team members too
- Shell plugins for common CLIs (AWS, GitHub, etc.)
- Secret references: `op://vault/item/field` — can be embedded in config

**Cons:**
- Requires 1Password Business/Teams subscription (~$8/user/month)
- CLI binary needs to be in the container image
- Service account token is itself a secret (bootstrap problem)

**Integration with OpenClaw:**
OpenClaw supports `SecretRef` with `source: "exec"`, which can call `op read`:
```json5
{
  "channels": {
    "slack": {
      "accounts": {
        "default": {
          "botToken": { "source": "exec", "id": "op://Agents/slack-main/bot-token" }
        }
      }
    }
  }
}
```

**Setup:**
```bash
# Install CLI (in container or init container)
# Set service account token
export OP_SERVICE_ACCOUNT_TOKEN="..."

# Read a secret
op read "op://AgentVault/github-pat/credential"

# Run a command with secrets injected
op run --env-file=.env.tpl -- ./my-script.sh
```

### 2. Kubernetes Secrets + External Secrets Operator

**Approach:** Store secrets in K8s, sync from external provider via ESO

**Pros:**
- Native to Kubernetes — no additional tooling in the container
- External Secrets Operator syncs from AWS Secrets Manager, Vault, 1Password, etc.
- Secrets mounted as env vars or files — standard K8s pattern
- Already partially in use (Anthropic API key is a K8s secret)

**Cons:**
- Secrets are base64 encoded, not encrypted at rest (unless using KMS)
- No native rotation automation
- Requires cluster-level tooling (ESO operator)
- Less convenient for local development / debugging

**OpenClaw integration:** Secrets as env vars work natively. File mounts work with `SecretRef` `source: "file"`.

### 3. HashiCorp Vault

**Approach:** Vault server with agent-based auth

**Pros:**
- Industry standard for secrets management
- Dynamic secrets (e.g. generate short-lived DB creds)
- Fine-grained policies per agent
- Full audit trail
- Auto-rotation for supported backends

**Cons:**
- Heavy — needs Vault server infrastructure
- Complex to operate (unsealing, HA, backups)
- Overkill for current team size
- Agent auth (AppRole/K8s auth) adds complexity

**OpenClaw integration:** Via `SecretRef` `source: "exec"` calling `vault kv get`.

### 4. Doppler

**Approach:** SaaS secrets manager with CLI

**Pros:**
- Simple SaaS — no infrastructure to manage
- Environment-based (dev/staging/prod)
- CLI injects secrets as env vars
- Rotation and versioning built-in
- Good GitHub/Slack integrations

**Cons:**
- SaaS dependency — secrets leave your infrastructure
- Pricing per secrets/projects
- Less mature than 1Password/Vault

### 5. Infisical

**Approach:** Open-source secrets management (self-hosted or cloud)

**Pros:**
- Open source — can self-host
- K8s operator available
- CLI for injection
- Good developer experience

**Cons:**
- Smaller community than alternatives
- Self-hosting adds operational burden

## Recommendation

**Short-term:** 1Password with Service Accounts. The team likely already uses 1Password, it's simple to set up, and it integrates with OpenClaw's `SecretRef` via `op read`. Service accounts work well in containers.

**Long-term:** If infrastructure grows, consider Kubernetes External Secrets Operator backed by 1Password or AWS Secrets Manager. This gives K8s-native secret injection without changing container code.

## OpenClaw SecretRef Integration

OpenClaw already supports `SecretRef` objects in config, which can source secrets from:
- **Environment variables** (`source: "env"`)
- **Files** (`source: "file"`)
- **Exec commands** (`source: "exec"`) — this enables 1Password CLI, Vault CLI, or any secret-fetching command

This means migration to a secrets manager doesn't require application changes — just update `openclaw.json` to use `SecretRef` instead of plaintext values.
