# Backup and Restore

How to backup and restore the OpenClaw deployment state so we can rebuild pods without losing configuration.

## Current Architecture

```
Pod (read-only root filesystem)
├── /app/                    → Container image (immutable)
│   ├── OpenClaw gateway
│   ├── Bundled skills
│   └── Node.js runtime
│
├── /home/node/.openclaw/    → PVC (19GB, persistent)
│   ├── openclaw.json        → Gateway config (agents, bindings, channels)
│   ├── credentials/         → Slack pairing, Jira token
│   ├── .git-credentials     → GitHub PAT
│   ├── .gitconfig           → Global git config (XDG)
│   ├── git/config           → Git credential helper config
│   ├── bin/                 → Custom scripts (jira-api.sh, etc.)
│   ├── workspace*/          → Agent workspaces (SOUL.md, IDENTITY.md, etc.)
│   ├── agents/              → Agent state dirs + session transcripts
│   ├── skills/              → Managed skills (shared across agents)
│   └── memory/              → Agent memory files
│
└── /home/node/              → Container image (read-only)
    ├── .bashrc              → Read-only
    └── .profile             → Read-only
```

## What survives a pod restart

✅ Everything on the PVC (`~/.openclaw/`) survives pod restarts because it's a PersistentVolumeClaim.

## What does NOT survive a pod rebuild

If the PVC is deleted or we deploy to a new cluster:

| Category | Location | Backup method |
|----------|----------|--------------|
| **Gateway config** | `openclaw.json` | Git (this repo) + secrets manager |
| **Agent workspaces** | `workspace-*/` | Git repos (each workspace has `.git`) |
| **Credentials** | `credentials/`, `.git-credentials` | Secrets manager (1Password) |
| **Slack pairings** | `credentials/slack-*-allowFrom.json` | Auto-regenerated on first DM |
| **Session transcripts** | `agents/*/sessions/` | Not critical — conversations restart |
| **Custom scripts** | `bin/` | Git (this repo, `scripts/`) |
| **Agent memory** | `memory/` | Git (each workspace) or backup script |
| **Installed binaries** | Not on PVC currently | Init container or custom image |

## Backup Strategy

### Tier 1: Config as Code (Git)

The `dametech/openclaw` repo is the source of truth for everything except secrets:

```
dametech/openclaw/
├── openclaw-deploy.sh        → Helm deployment script
├── openclaw-delete.sh        → Cleanup script
├── openclaw-portforward.sh   → Port forwarding helper
├── terraform/                → Infrastructure (K8s service, Route53, ACM certs)
├── setup-slack-integration.sh → Slack setup automation
├── openclaw.json.template    → Config with SecretRef placeholders (TODO)
├── templates/                → Agent workspace templates (AGENTS.md, etc.)
├── scripts/                  → Agent creation and wiring scripts
├── docs/                     → All documentation
└── team.yaml                 → Team definition (TODO)
```

**What to commit:**
- `openclaw.json` template (secrets replaced with SecretRef or placeholders)
- Agent workspace templates
- Setup scripts
- Documentation

**What NOT to commit:**
- Actual tokens, keys, or credentials
- Session transcripts
- Pairing approval files (auto-regenerated)

### Tier 2: Secrets (1Password)

All credentials stored in 1Password, fetched at runtime via `op` CLI or SecretRef:
- Anthropic API key
- Slack bot tokens (per agent)
- Slack app tokens (per agent)
- GitHub PAT
- Jira API token
- Gateway auth token

### Tier 3: Init Container

For binaries and tools that need to be available at startup:

```yaml
initContainers:
  - name: init-tools
    image: alpine:latest
    command: ['sh', '-c']
    args:
      - |
        # Install 1Password CLI
        wget -O /tools/op https://cache.agilebits.com/dist/1P/op2/pkg/...
        chmod +x /tools/op
        
        # Install gh CLI
        wget -O /tools/gh https://github.com/cli/cli/releases/...
        chmod +x /tools/gh
        
        # Install kubectl
        wget -O /tools/kubectl https://dl.k8s.io/release/.../bin/linux/amd64/kubectl
        chmod +x /tools/kubectl
    volumeMounts:
      - name: tools
        mountPath: /tools

containers:
  - name: main
    volumeMounts:
      - name: tools
        mountPath: /home/node/.openclaw/bin/tools
    env:
      - name: PATH
        value: "/home/node/.openclaw/bin/tools:/usr/local/bin:/usr/bin:/bin"
```

### Tier 4: Custom Container Image (long-term)

For a production-ready setup, build a custom image with all tools pre-installed:

```dockerfile
FROM ghcr.io/openclaw/openclaw:latest

USER root
RUN apt-get update && apt-get install -y \
    gh \
    kubectl \
    && rm -rf /var/lib/apt/lists/*

# Install 1Password CLI
RUN wget -qO- https://cache.agilebits.com/dist/1P/op2/pkg/... | tar xz -C /usr/local/bin/

USER node
```

## Restore Procedure

### From scratch (new PVC, new pod)

1. **Deploy pod** with custom image or init containers for tools
2. **Clone this repo** into the workspace
3. **Run provisioning script** (future: `scripts/provision-team.sh` reads `team.yaml`)
4. **Inject secrets** from 1Password (or manually for first bootstrap)
5. **Create Slack apps** (if not already created — app IDs are stable)
6. **Wire Slack tokens** via `scripts/wire-agent-slack.sh`
7. **Approve pairings** on first DM from each user
8. **Verify** with `openclaw channels status --probe` and `openclaw agents list --bindings`

### From PVC backup (faster)

If you snapshot the PVC before destroying:
1. Restore PVC from snapshot
2. Deploy pod with same image
3. `kill -HUP 1` to reload config
4. Verify with probe

## TODO

- [ ] Create `openclaw.json.template` with SecretRef placeholders
- [ ] Set up 1Password and migrate secrets
- [ ] Create init container config for tool installation (op, gh, kubectl)
- [ ] Build custom container image with all tools
- [ ] Create `scripts/provision-team.sh` that reads team definition
- [ ] Set up PVC snapshot schedule (K8s VolumeSnapshot)
- [ ] Test full restore procedure from scratch
- [ ] Add backup verification to heartbeat checks
