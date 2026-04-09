# OpenClaw Kubernetes Deployment

This directory contains scripts to deploy and manage OpenClaw, an open-source AI automation framework, on your Kubernetes cluster.

## What is OpenClaw?

OpenClaw is your personal AI assistant that runs in a containerized environment. It provides:
- AI-powered code assistance using Claude models
- Browser automation capabilities with headless Chrome
- Persistent workspace and session management
- Secure, isolated execution environment

## Prerequisites

Before deploying OpenClaw, ensure you have:

1. **kubectl** - Kubernetes command-line tool
2. **helm** - Kubernetes package manager (v4.0+)
3. **Kubernetes cluster access** - The `~/.kube/au01-0.yaml` kubeconfig file
4. **AWS Bedrock credentials** - `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

## Quick Start

### 1. Deploy OpenClaw

```bash
./openclaw-deploy.sh
```

You can also deploy non-interactively with an explicit release name:

```bash
./openclaw-deploy.sh --release-name oc-sm
```

This script will:
- Check prerequisites
- Check for existing PVCs owned by the target release and require confirmation before deleting them
- Uninstall the existing release and delete release-owned ConfigMaps before reusing the same release name
- Prompt for AWS Bedrock credentials (or use `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and optional `AWS_SESSION_TOKEN`)
- Set up the Helm repository
- Create the `openclaw` namespace
- Store your Bedrock credentials securely in a Kubernetes secret
- Deploy OpenClaw using Helm
- Validate the rendered `openclaw.json` locally before Helm runs
- Copy repo-managed workspace docs such as `openclaw/workspace/BOOTSTRAP.md` and `openclaw/workspace/TOOLS.md` into the pod workspace on redeploy
- Display the gateway token for authentication

To deploy a new OpenClaw instance against an existing PVC instead of creating a new data claim:

```bash
./openclaw-deploy.sh --release-name oc-sm-restore --existing-pvc oc-sm-restore-data
```

This is useful for restore and recovery workflows where you want to:
- populate a new PVC from backup
- launch a separate validation instance against that PVC
- inspect the restored state before cutting over

Important: `--existing-pvc` only attaches a PVC that already exists in Kubernetes. It does not restore from S3 by itself. Internally the deploy script disables the chart's default dynamic `data` volume and mounts your supplied PVC at `/home/node/.openclaw` through a separate persistence entry.

If PVCs already exist for the same release name, the deploy script now warns and asks for confirmation before deleting them. Answering `n` cancels the deploy.

### 2. Deploy Optional Ollama Embeddings Service

If you want OpenClaw pods to use a shared in-cluster Ollama service for semantic memory embeddings, deploy it separately:

```bash
set -a
. ./deploy.env
set +a
./deploy-ollama-embeddings.sh
```

Relevant `deploy.env` settings:

```bash
OLLAMA_EMBEDDINGS_MODEL=nomic-embed-text
```

This creates:
- a dedicated Ollama deployment in the `openclaw` namespace
- a `ClusterIP` service reachable at `http://ollama-embeddings.openclaw.svc.cluster.local:11434`
- a `NetworkPolicy` allowing ingress only from OpenClaw pods

OpenClaw pods now assume that shared service exists and use it for semantic memory embeddings by default. The only Ollama-related setting you normally need in `deploy.env` is:

```bash
OLLAMA_EMBEDDINGS_MODEL=nomic-embed-text
```

Then run `./openclaw-deploy.sh` for each OpenClaw instance. The service name is fixed as `ollama-embeddings`, so there is no separate prompt or env var for it.

### 3. Access OpenClaw

Start port forwarding to access the web interface:

```bash
# Use default port 18789
./openclaw-portforward.sh

# Or specify a custom local port
./openclaw-portforward.sh -p 8080
./openclaw-portforward.sh --port 9000

# Legacy positional argument also supported
./openclaw-portforward.sh 8080
```

Then open your browser to the URL displayed by the script (e.g., **http://localhost:18789**).

Authenticate using the gateway token displayed by the script.

### 4. Clean Up

To remove OpenClaw from your cluster:

```bash
./openclaw-delete.sh
```

This script will prompt you to:
- Confirm deletion
- Delete the release PersistentVolumeClaim (data)
- Delete release-owned ConfigMaps
- Preserve the `openclaw` namespace

### 5. Configure PVC Backups

To create the cluster-side PVC backup workflow for all OpenClaw PVCs in the `openclaw` namespace:

```bash
./setup-pvc-backup.sh
```

You can also provide values non-interactively:

```bash
./setup-pvc-backup.sh \
  --bucket dame-openclaw-backup \
  --access-key AKIA... \
  --secret-key '...' \
  --region ap-southeast-2 \
  --cluster au01-0
```

This script:
- checks cluster access using your kubeconfig
- derives the default backup cluster id from the active kube context unless `--cluster` is supplied
- creates or updates the `openclaw-backup-aws` secret
- creates or updates the `openclaw-backup-script` ConfigMap from `scripts/openclaw-backup-s3.py`
- applies `k8s/pvc-backup-cronjob.yaml`
- prints the manual trigger command for the backup dispatcher

The backup dispatcher runs as a Kubernetes `CronJob`, so once applied it runs on the cluster and does not depend on your laptop remaining online.

Manual trigger:

```bash
kubectl create job --from=cronjob/openclaw-pvc-backup-dispatcher \
  -n openclaw openclaw-pvc-backup-dispatcher-manual-$(date +%s)
```

To back up just one OpenClaw release/PVC on demand before a redeploy, use:

```bash
./backup-pvc-to-s3.sh --release-name oc-marc
```

If more than one PVC is labeled for that release, specify the PVC explicitly:

```bash
./backup-pvc-to-s3.sh --release-name oc-marc --pvc-name oc-marc
```

This one-off backup script:
- checks cluster access using your kubeconfig
- verifies `openclaw-backup-aws` and `openclaw-backup-script` already exist
- resolves the PVC from `app.kubernetes.io/instance=<release>` if you do not pass `--pvc-name`
- creates one backup `Job` using the same Python worker used by the CronJob
- waits for completion by default and prints the job logs

Useful options:

```bash
./backup-pvc-to-s3.sh --release-name oc-marc --cluster au01-0
./backup-pvc-to-s3.sh --release-name oc-marc --timeout 45m
./backup-pvc-to-s3.sh --release-name oc-marc --no-wait
```

Useful checks:

```bash
kubectl get cronjob -n openclaw openclaw-pvc-backup-dispatcher
kubectl get jobs -n openclaw
kubectl get pods -n openclaw | grep openclaw-pvc-backup
kubectl logs -n openclaw job/<job-name>
```

Each child backup job discovers one PVC, reads its `app.kubernetes.io/instance` label, mounts that PVC read-only, and uploads a backup to:

```text
s3://<bucket>/openclaw-backups/<cluster>/<instance>/<pvc>/<timestamp>.tar.gz
```

For example:

```text
s3://dame-openclaw-backup/openclaw-backups/au01-0/oc-sm/openclaw-data/2026-04-07T020000Z.tar.gz
```

### 6. Restore a PVC Backup

To restore one backup from S3 into a new PVC and then launch a new OpenClaw instance against it:

```bash
./restore-pvc-backup.sh \
  --s3-uri s3://dame-openclaw-backup/openclaw-backups/au01-0/oc-sm/openclaw-data/2026-04-07T020000Z.tar.gz \
  --pvc-name oc-sm-restore-data \
  --release-name oc-sm-restore
```

This script:
- checks cluster access
- verifies the `openclaw-backup-aws` secret exists
- creates the target PVC
- creates a temporary restore pod in the cluster
- downloads the selected backup from S3 into that pod
- extracts it into the PVC
- prints the matching `openclaw-deploy.sh --existing-pvc` command

The final deploy step is still separate by design:

```bash
./openclaw-deploy.sh --release-name oc-sm-restore --existing-pvc oc-sm-restore-data
```

The separation is intentional so you can inspect or validate the restored PVC before starting a new OpenClaw instance against it.

When deploying against an existing or restored PVC, the deploy script now preserves selected runtime config from the existing `openclaw.json` when available:
- `gateway.auth.token`
- `channels.slack`
- `channels.msteams`

That prevents a restore-based redeploy from wiping previously configured Slack or Teams channel blocks that were stored on the PVC. The base deploy also now includes optional `envFrom` references for `${RELEASE_NAME}-slack-tokens` and `${RELEASE_NAME}-teams-credentials`, so restored channel configs can start working again immediately if those secrets still exist in the cluster.

## Deployment Architecture

### Components Deployed

- **Main Container**: OpenClaw gateway and agent runtime
  - Uses Claude Sonnet 4.6 on AWS Bedrock by default
  - Binds to the pod network (`lan`) so Kubernetes health probes can reach it
  - Port 18789 for web interface

- **Chromium Sidecar**: Headless browser for automation
  - Chrome DevTools Protocol on port 9222
  - Enables web scraping and browser automation

- **Init Containers**:
  - `init-dev-tools`: Installs the shared PVC-backed toolchain into `~/.openclaw/bin`
  - `init-config`: Replaces runtime config with the rendered Helm configuration
  - `init-skills`: Installs ClawHub skills (weather, gog)

- **Optional Ollama Embeddings Deployment**: Separate in-cluster embeddings service
  - Deployed with `./deploy-ollama-embeddings.sh`
  - Exposes Ollama only on internal service port `11434`
  - Intended only for semantic memory embeddings, not chat/completions

### Storage

- **PersistentVolumeClaim**: 5Gi using `talos-hostpath` storage class
  - Stores workspace, sessions, and configuration
  - Persists across pod restarts
  - Also stores the per-pod toolchain under `~/.openclaw/bin`, `~/.openclaw/tools`, and `~/.openclaw/.tool-versions`

### Security

- **Bedrock Credentials**: Stored as Kubernetes secret (`openclaw-env-secret`)
- **Control UI Origins**: Browser access is restricted to explicit allowed origins
- **Recommended Access Path**: Use `kubectl port-forward` to `localhost:18789`
- **Security Context**:
  - Read-only root filesystem
  - Non-root user (UID 1000)
  - All capabilities dropped

### Local Shell Tooling

Each pod now gets a PVC-backed dev-tools layer during startup. The `init-dev-tools` container installs a stable local toolchain into `~/.openclaw/bin`, and the main container prepends that directory to `PATH`.

This section is about binaries available inside the pod. Agent-callable shell or exec tools are separate OpenClaw tool definitions; installing binaries on `PATH` does not by itself make them appear as structured tools in the agent context.

Common local shell tools available through this path include:
- `jq`
- `kubectl`
- `helm`
- `gh`
- `go`
- `terraform`
- `op`
- `aws`
- `codex`

The install is idempotent and version-pinned in [scripts/install-dev-tools.sh](/mnt/c/projects/openclaw/scripts/install-dev-tools.sh). Tools persist on the PVC across pod restarts without requiring a writable root filesystem.

## Configuration Files

### Helm Values (`/tmp/openclaw-values.yaml`)

The deployment uses custom Helm values:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          args:
            - gateway
            - --bind
            - lan  # Required so Kubernetes probes can reach the gateway
            - --port
            - "18789"
          envFrom:
            - secretRef:
                name: openclaw-env-secret  # Bedrock credentials secret

  configMaps:
    config:
      data:
        openclaw.json: |
          {
            "gateway": {
              "mode": "local",
              "controlUi": {
                "allowedOrigins": [
                  "http://127.0.0.1:18789",
                  "http://localhost:18789"
                ]
              }
            },
            "agents": {
              "defaults": {
                "workspace": "/home/node/.openclaw/workspace",
                "model": {
                  "primary": "amazon-bedrock/global.anthropic.claude-sonnet-4-6"
                },
                "models": {
                  "amazon-bedrock/global.anthropic.claude-sonnet-4-6": {
                    "params": {
                      "cacheRetention": "ephemeral"
                    }
                  },
                  "amazon-bedrock/global.anthropic.claude-opus-4-6-v1": {
                    "params": {
                      "cacheRetention": "ephemeral"
                    }
                  },
                  "amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0": {
                    "params": {
                      "cacheRetention": "none"
                    }
                  }
                },
                "userTimezone": "Australia/Brisbane",
                "timeoutSeconds": 600,
                "maxConcurrent": 1
              },
              "list": [
                {
                  "id": "main",
                  "default": true,
                  "identity": {
                    "name": "OpenClaw",
                    "emoji": "🦞"
                  },
                  "model": "amazon-bedrock/global.anthropic.claude-sonnet-4-6"
                }
              ]
            },
            "models": {
              "providers": {
                "amazon-bedrock": {
                  "baseUrl": "https://bedrock-runtime.ap-southeast-2.amazonaws.com",
                  "apiKey": "aws-sdk",
                  "api": "bedrock-converse-stream",
                  "models": [
                    {
                      "id": "global.anthropic.claude-sonnet-4-6",
                      "name": "Claude Sonnet 4.6 (Bedrock)",
                      "api": "bedrock-converse-stream",
                      "reasoning": true,
                      "input": ["text", "image"],
                      "cost": {
                        "input": 3,
                        "output": 15,
                        "cacheRead": 0.3,
                        "cacheWrite": 3.75
                      },
                      "contextWindow": 200000,
                      "maxTokens": 8000
                    },
                    {
                      "id": "global.anthropic.claude-opus-4-6-v1",
                      "name": "Claude Opus 4.6 (Bedrock)",
                      "api": "bedrock-converse-stream",
                      "reasoning": true,
                      "input": ["text", "image"],
                      "cost": {
                        "input": 5,
                        "output": 25,
                        "cacheRead": 0.5,
                        "cacheWrite": 6.25
                      },
                      "contextWindow": 200000,
                      "maxTokens": 8000
                    },
                    {
                      "id": "global.anthropic.claude-haiku-4-5-20251001-v1:0",
                      "name": "Claude Haiku 4.5 (Bedrock)",
                      "api": "bedrock-converse-stream",
                      "reasoning": false,
                      "input": ["text", "image"],
                      "cost": {
                        "input": 1,
                        "output": 5,
                        "cacheRead": 0.1,
                        "cacheWrite": 1.25
                      },
                      "contextWindow": 200000,
                      "maxTokens": 4096
                    }
                  ]
                }
              },
              "bedrockDiscovery": {
                "enabled": false,
                "region": "ap-southeast-2",
                "providerFilter": ["anthropic", "amazon"],
                "refreshInterval": 3600,
                "defaultContextWindow": 32000,
                "defaultMaxTokens": 4096
              }
            }
          }

  persistence:
    data:
      enabled: true
      type: persistentVolumeClaim
      accessMode: ReadWriteOnce
      size: 5Gi
      storageClass: talos-hostpath
```

### Runtime Configuration

OpenClaw's runtime configuration is stored at `/home/node/.openclaw/openclaw.json` in the pod:

- **Gateway**: Token authentication, pod-network bind mode, explicit localhost Control UI origins
- **Agents**: Single `main` agent uses Bedrock Sonnet by default and can switch to Opus or Haiku using the configured per-model entries and Bedrock provider metadata
- **Memory Search**: `agents.defaults.memorySearch` is configured by default with `provider: "ollama"` and `remote.baseUrl` set to the shared in-cluster Ollama service
- **Browser**: Chromium CDP integration
- **Tools**: Full profile with web fetch enabled

### Ollama Embeddings Service

The Ollama deployment is managed separately from OpenClaw so multiple OpenClaw pods can share one embeddings service.

Deploy it with:

```bash
set -a
. ./deploy.env
set +a
./deploy-ollama-embeddings.sh
```

Verify it with:

```bash
export KUBECONFIG=~/.kube/au01-0.yaml
kubectl get deploy,svc,networkpolicy -n openclaw | grep ollama
kubectl logs -n openclaw deployment/ollama-embeddings
```

OpenClaw pods are configured to use the shared Ollama service for semantic memory by default. The only Ollama-specific setting you normally need is:

```bash
OLLAMA_EMBEDDINGS_MODEL=nomic-embed-text
```

Then deploy or redeploy that OpenClaw instance with `./openclaw-deploy.sh`. The resulting `openclaw.json` points semantic memory embeddings at:

```text
http://ollama-embeddings.openclaw.svc.cluster.local:11434
```

## Manual Commands

### View Logs

```bash
export KUBECONFIG=~/.kube/au01-0.yaml
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main -f
```

### Check Pod Status

```bash
kubectl get pods -n openclaw
```

### Interactive Shell

```bash
kubectl exec -it -n openclaw deployment/openclaw -c main -- /bin/bash
```

### View Configuration

```bash
kubectl exec -n openclaw deployment/openclaw -c main -- cat /home/node/.openclaw/openclaw.json
```

### Restart Deployment

```bash
kubectl rollout restart deployment/openclaw -n openclaw
```

### Sync Shared Plugins, Skills, And Workspace

To push the repo's current `openclaw/plugins/`, `openclaw/skills/`, and `openclaw/workspace/` folders into every running OpenClaw deployment, then restart each deployment:

```bash
./sync-openclaw-shared-config.sh
```

This script:
- detects all deployments labeled as OpenClaw in the `openclaw` namespace
- copies `openclaw/plugins/` into `~/.openclaw/plugins/`
- copies `openclaw/skills/` into `~/.openclaw/workspace/skills/`
- copies `openclaw/workspace/` into `~/.openclaw/workspace/`
- includes repo-managed workspace docs such as `BOOTSTRAP.md` and `TOOLS.md`
- overwrites matching files and adds new files
- leaves pod-only files in place
- does not overwrite `~/.openclaw/openclaw.json`; that file is still managed by deploy
- restarts each deployment
- waits for rollout completion and prints status

### Manual Port Forwarding

If you need more control over port forwarding:

```bash
export KUBECONFIG=~/.kube/au01-0.yaml

# Forward to default port
kubectl port-forward -n openclaw svc/openclaw 18789:18789

# Forward to custom local port
kubectl port-forward -n openclaw svc/openclaw 8080:18789
```

## Troubleshooting

### Pod Not Starting

Check pod events:
```bash
kubectl describe pod -n openclaw -l app.kubernetes.io/name=openclaw
```

### Connection Refused

Ensure port-forward is running:
```bash
./openclaw-portforward.sh
```

### Authentication Failed

Retrieve the latest gateway token:
```bash
kubectl exec -n openclaw deployment/openclaw -c main -- \
  cat /home/node/.openclaw/openclaw.json | grep -o '"token": "[^"]*"' | cut -d'"' -f4
```

### Check Service Status

```bash
kubectl get all -n openclaw
```

### Ollama Embeddings Not Reachable

Check that the Ollama deployment and service exist:

```bash
kubectl get deploy,svc,networkpolicy -n openclaw | grep ollama
kubectl logs -n openclaw deployment/ollama-embeddings
```

Then confirm the OpenClaw pod is configured to use it:

```bash
kubectl exec -n openclaw deployment/openclaw -c main -- \
  cat /home/node/.openclaw/openclaw.json | grep -n 'memorySearch\|ollama'
```

## Helm Repository

OpenClaw is installed from the community Helm chart:

- **Repository**: https://serhanekicii.github.io/openclaw-helm
- **Chart**: `openclaw-community/openclaw`
- **Version**: 1.5.4 (App: 2026.3.13-1)

## Cluster Information

- **Cluster**: au01-0
- **Kubernetes Version**: v1.33.0
- **Platform**: Talos Linux
- **Worker Nodes**: 4 active nodes
- **Control Plane**: talos-cluster-one-cp-01

## Resources & Documentation

### Official Documentation
- [OpenClaw Kubernetes Guide](https://docs.openclaw.ai/install/kubernetes)
- [OpenClaw Docker Guide](https://docs.openclaw.ai/install/docker)

### Community Resources
- [Kubernetes Operator](https://github.com/openclaw-rocks/k8s-operator)
- [Helm Chart Repository](https://github.com/serhanekicii/openclaw-helm)
- [Deployment Tutorials](https://lumadock.com/tutorials/openclaw-docker-kubernetes)

### API Provider
- [Amazon Bedrock](https://aws.amazon.com/bedrock/) - Host for Claude models
- [AWS Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)

## Environment Variables

The following environment variables can be used:

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key for Bedrock | Required |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key for Bedrock | Required |
| `AWS_SESSION_TOKEN` | Optional AWS session token | Optional |
| `OLLAMA_EMBEDDINGS_MODEL` | Ollama embedding model pulled by the Ollama pod and referenced by OpenClaw | `nomic-embed-text` |
| `KUBECONFIG` | Path to kubeconfig file | `~/.kube/au01-0.yaml` |

## Advanced Usage

### Enable Web Search

Modify the Helm values to enable web search capabilities:

```yaml
app-template:
  configMaps:
    config:
      data:
        openclaw.json: |
          {
            "tools": {
              "web": {
                "search": {
                  "enabled": true
                }
              }
            }
          }
```

### Add Chat Channels

Slack setup in this repo is release-specific and script-driven.

1. Create or update the Slack app using [slack-app-manifest.yaml](./slack-app-manifest.yaml).
2. Generate:
   - a Socket Mode app token (`xapp-...`)
   - a bot token (`xoxb-...`)
3. Run:

```bash
./setup-slack-integration.sh
```

The script will:
- ask for the target release name, for example `oc-marc`
- create or update the `${RELEASE_NAME}-slack-tokens` secret
- read the current `/home/node/.openclaw/openclaw.json` from the pod
- merge a `channels.slack` block into that config instead of replacing it
- keep Slack tokens in Kubernetes secrets and reference them through env placeholders
- run `helm upgrade --reuse-values`
- check recent Slack connection logs
- offer to launch the pairing helper

The base deploy template now includes a disabled `channels.slack` block by default. Deploy also preserves an existing live or restored `channels.slack` block when available, so a redeploy does not wipe previously configured Slack settings from `openclaw.json`. The main container also includes an optional `${RELEASE_NAME}-slack-tokens` `envFrom` reference, so a restored Slack channel can come back automatically when that secret is still present. The Slack setup script is still the step that actually enables the channel and creates or refreshes the token secret when needed.

The main container ends up with two relevant secrets in `envFrom`:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          envFrom:
            - secretRef:
                name: <release>-env-secret
            - secretRef:
                name: <release>-slack-tokens
                optional: true
```

### Slack Pairing

Slack setup does not complete pairing automatically. After the pod reports Slack connected:

1. Open Slack and send a DM to the bot, or invite it to a channel and mention it.
2. Run the pairing helper:

```bash
./approve-slack-pairing.sh --release oc-marc
```

The helper:
- waits for the pod to be ready
- prompts for the Slack pairing code immediately
- can optionally list pending Slack pairings
- approves the code with the OpenClaw CLI inside the pod

If you restore a PVC that was already Slack-enabled, redeploy should now preserve the stored Slack channel block automatically and reattach the optional Slack secret reference. In that case you only need to rerun `setup-slack-integration.sh` if the `${RELEASE_NAME}-slack-tokens` secret is missing or stale, and you only need to rerun pairing if Slack/OpenClaw asks for it again during testing.

If you already know the code, you can approve it directly:

```bash
./approve-slack-pairing.sh --release oc-marc --code ABC123
```

### Microsoft Teams

Teams setup in this repo is also release-specific, but it is not built into the base deploy the way Slack now is.

Use:

```bash
./setup-msteams-integration.sh
```

The Teams setup flow:
- copies the vendored local Teams plugin from `openclaw/plugins/msteams` into the target pod
- installs that plugin through the OpenClaw CLI in the pod
- creates the `${RELEASE_NAME}-teams-credentials` secret
- creates the Teams webhook service and ingress
- patches `channels.msteams` into `openclaw.json`
- restarts the deployment

Deploy now preserves an existing live or restored `channels.msteams` block from `openclaw.json`, and the base deploy includes an optional `${RELEASE_NAME}-teams-credentials` `envFrom` reference. But Teams still depends on the extra runtime resources created by `setup-msteams-integration.sh`:
- the installed `msteams` plugin
- the Teams credentials secret
- the Teams webhook service
- the Teams ingress

If you restore a PVC that was already Teams-enabled, redeploy should preserve the `channels.msteams` block. You still need to make sure the plugin, secret, service, and ingress exist in the cluster before expecting Teams to work again.

### Increase Resources

For heavier workloads, adjust resource limits:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 4000m
              memory: 4Gi
```

## License

OpenClaw is open-source software. Check the [official repository](https://github.com/openclaw-rocks) for license details.

## Support

For issues or questions:
- Review the [official documentation](https://docs.openclaw.ai)
- Check the [GitHub issues](https://github.com/openclaw-rocks/k8s-operator/issues)
- Consult community tutorials at [LumaDock](https://lumadock.com/tutorials/openclaw-docker-kubernetes)

---

**Last Updated**: March 2026
**OpenClaw Version**: 2026.3.13-1
**Helm Chart Version**: 1.5.4
