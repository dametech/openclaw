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
4. **Anthropic API key** - Get one from [console.anthropic.com](https://console.anthropic.com)

## Quick Start

### 1. Deploy OpenClaw

```bash
./openclaw-deploy.sh
```

This script will:
- Check prerequisites
- Prompt for your Anthropic API key (or use `$ANTHROPIC_API_KEY` env var)
- Set up the Helm repository
- Create the `openclaw` namespace
- Store your API key securely in a Kubernetes secret
- Deploy OpenClaw using Helm
- Display the gateway token for authentication

### 2. Access OpenClaw

Start port forwarding to access the web interface:

```bash
./openclaw-portforward.sh
```

Then open your browser to: **http://localhost:18789**

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
  - Uses Claude Opus 4.6 model
  - Binds to loopback interface (127.0.0.1) for security
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

- **API Key**: Stored as Kubernetes secret (`openclaw-env-secret`)
- **Loopback Binding**: Service only accessible via port-forward
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
            - loopback  # Secure local binding
            - --port
            - "18789"
          envFrom:
            - secretRef:
                name: openclaw-env-secret  # API key secret

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

- **Gateway**: Token authentication, loopback mode
- **Browser**: Chromium CDP integration
- **Agents**: Claude Opus 4.6 with cache retention
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
- [Anthropic Console](https://console.anthropic.com) - Get API keys
- [Claude API Docs](https://docs.anthropic.com)

## Environment Variables

The following environment variables can be used:

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude models | Required |
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
