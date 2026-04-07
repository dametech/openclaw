# Anthropic API Authentication Setup for OpenClaw

## Issue
OpenClaw agents were failing with error:
```
agent failed before reply: No API key found for provider "anthropic".
Auth store: /home/node/.openclaw/agents/main/agent/auth-profiles.json
```

## Solution Implemented

### 1. Stored API Key in 1Password
- Created item: "Anthropic API Key Openclaw"
- Vault: Infrastructure
- Type: Secure Note
- Field: notesPlain contains the full API key

### 2. Created auth-profiles.json for All Agents

Created `/home/node/.openclaw/agents/*/agent/auth-profiles.json` for each agent:
- main
- davo
- edgex
- siteconfig
- siteuis
- minercode
- minermaint

**File structure:**
```json
{
  "version": 1,
  "profiles": {
    "anthropic:claude-cli": {
      "type": "api_key",
      "mode": "static",
      "key": "sk-ant-api03-...",
      "provider": "anthropic"
    }
  }
}
```

### 3. Reloaded Secrets
```bash
kubectl exec -n openclaw deploy/openclaw -c main -- node dist/index.js secrets reload
```

## Verification

### Check auth files exist:
```bash
kubectl exec -n openclaw deploy/openclaw -c main -- \
  find /home/node/.openclaw/agents -name "auth-profiles.json"
```

### Verify 1Password access:
```bash
kubectl exec -n openclaw deploy/openclaw -c main -- \
  /home/node/.openclaw/bin/op item get "Anthropic API Key Openclaw" \
  --vault Infrastructure --fields notesPlain
```

### Check for API key errors in logs:
```bash
kubectl logs -n openclaw deploy/openclaw -c main --tail=50 | \
  grep -i "no api key"
```

## Persistence

### Files are Persistent
The auth-profiles.json files are stored in `/home/node/.openclaw/agents/`, which is mounted from a PersistentVolumeClaim. They will survive pod restarts.

### Backup Location
S3 backup: `s3://<your-bucket>/<your-backup-prefix>/`

## Recovery Procedure

If auth-profiles.json files are lost after a pod restart:

```bash
# Recreate all auth-profiles.json files from 1Password
kubectl exec -n openclaw deploy/openclaw -c main -- bash -c '
API_KEY=$(/home/node/.openclaw/bin/op item get "Anthropic API Key Openclaw" \
  --vault Infrastructure --fields notesPlain)

for agent in main davo edgex siteconfig siteuis minercode minermaint; do
  mkdir -p /home/node/.openclaw/agents/$agent/agent
  cat > /home/node/.openclaw/agents/$agent/agent/auth-profiles.json << EOF
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
  echo "Created auth-profiles.json for $agent"
done
'

# Reload secrets
kubectl exec -n openclaw deploy/openclaw -c main -- \
  node dist/index.js secrets reload
```

## Configuration Status

### 1Password Integration
- ✓ OP_SERVICE_ACCOUNT_TOKEN configured via Kubernetes secret
- ✓ op CLI installed at `/home/node/.openclaw/bin/op`
- ✓ Access to Infrastructure vault verified

### Filesystem
- ✓ Writable filesystem enabled (`readOnlyRootFilesystem: false`)
- ✓ PVC-backed storage for persistence

### Authentication
- ✓ Anthropic API key stored in 1Password
- ✓ auth-profiles.json created for all 7 agents
- ✓ Secrets reloaded successfully

## Future Improvements

1. **Automate auth-profiles.json creation** - Add init container to create these files on pod startup
2. **Use 1Password references** - Consider if OpenClaw supports direct 1Password integration
3. **Add to backup verification** - Ensure auth-profiles.json are included in S3 backups

## Related Documentation
- `helm/values-1password.yaml` - 1Password Helm configuration
- `scripts/setup-1password.sh` - 1Password setup script
- `helm/values-writable-fs.yaml` - Writable filesystem configuration
