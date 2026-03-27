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

This script will:
- Check prerequisites
- Prompt for AWS Bedrock credentials (or use `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and optional `AWS_SESSION_TOKEN`)
- Set up the Helm repository
- Create the `openclaw` namespace
- Store your Bedrock credentials securely in a Kubernetes secret
- Deploy OpenClaw using Helm
- Display the gateway token for authentication

### 2. Access OpenClaw

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

### 3. Clean Up

To remove OpenClaw from your cluster:

```bash
./openclaw-delete.sh
```

This script will prompt you to:
- Confirm deletion
- Optionally delete the PersistentVolumeClaim (data)
- Optionally delete the namespace

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
  - `init-config`: Merges Helm configuration with runtime config
  - `init-skills`: Installs ClawHub skills (weather, gog)

### Storage

- **PersistentVolumeClaim**: 5Gi using `talos-hostpath` storage class
  - Stores workspace, sessions, and configuration
  - Persists across pod restarts

### Security

- **Bedrock Credentials**: Stored as Kubernetes secret (`openclaw-env-secret`)
- **Control UI Origins**: Browser access is restricted to explicit allowed origins
- **Recommended Access Path**: Use `kubectl port-forward` to `localhost:18789`
- **Security Context**:
  - Read-only root filesystem
  - Non-root user (UID 1000)
  - All capabilities dropped

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
- **Browser**: Chromium CDP integration
- **Tools**: Full profile with web fetch enabled

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

Configure Telegram, Discord, or Slack integration by adding credentials:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          envFrom:
            - secretRef:
                name: openclaw-env-secret
            - secretRef:
                name: openclaw-chat-credentials
```

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
