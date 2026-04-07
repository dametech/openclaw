# Microsoft Teams Integration Setup Guide

**OpenClaw Version**: 2026.3.13+
**Status**: Plugin-based (as of January 2026)
**Bot Type**: Single Tenant (Multi-tenant deprecated July 31, 2025)

## Overview

Microsoft Teams integration uses the **Azure Bot Framework** with a webhook-based architecture. Unlike Slack's Socket Mode, Teams requires a **publicly accessible webhook endpoint**.

### Architecture Flow

```
User in Teams → Bot Framework Service → Webhook POST to /api/messages
→ OpenClaw processes → Reply via Bot Framework API → Teams delivers response
```

### Key Differences from Slack

| Feature | Teams | Slack |
|---------|-------|-------|
| Plugin | Required (`@openclaw/msteams`) | Built-in |
| Connection | Webhook (HTTP) | Socket Mode (WebSocket) |
| Public URL | **Required** | Not required |
| Credentials | 3 values (App ID, secret, tenant) | 2 tokens |
| Webhook Port | 3978 (default) | N/A |
| File uploads | SharePoint integration needed | Built-in |

## Prerequisites

Before starting, you need:

1. **Azure subscription** with permissions to create:
   - Azure Bot Service
   - App Registrations in Entra ID (Azure AD)

2. **Microsoft Teams** workspace admin access

3. **Public webhook endpoint** options:
   - Kubernetes Ingress with TLS certificate
   - ngrok tunnel (for testing)
   - Tailscale Funnel
   - CloudFlare Tunnel

4. **OpenClaw** deployed to Kubernetes

## Phase 1: Azure Bot Registration

### Step 1: Create App Registration

1. Go to [Azure Portal - App Registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)
2. Click **"New registration"**
3. Configure:
   - **Name**: `OpenClaw Teams Bot`
   - **Supported account types**: `Accounts in this organizational directory only (Single tenant)`
   - **Redirect URI**: Leave empty for now
4. Click **"Register"**

5. On the Overview page, **COPY these values**:
   - **Application (client) ID** → This is your `appId`
   - **Directory (tenant) ID** → This is your `tenantId`

### Step 2: Create Client Secret

1. In your App Registration, go to **"Certificates & secrets"**
2. Click **"New client secret"**
3. Description: `openclaw-teams-secret`
4. Expires: Choose duration (90 days, 180 days, or custom)
5. Click **"Add"**
6. **IMMEDIATELY COPY the secret Value** → This is your `appPassword`
   ⚠️ You can only see this ONCE! Store it in 1Password immediately!

### Step 3: Create Azure Bot Service

1. Go to [Create Azure Bot](https://portal.azure.com/#create/Microsoft.AzureBot)
2. Configure:
   - **Bot handle**: `openclaw-teams-bot` (must be globally unique)
   - **Subscription**: Select your subscription
   - **Resource group**: Create new or use existing
   - **Pricing tier**: `F0 (Free)` for testing
   - **Type**: `Single Tenant` ⚠️ Multi-tenant deprecated!
   - **Microsoft App ID**: Select `Use existing app registration`
   - **App ID**: Paste your Application (client) ID from Step 1
3. Click **"Review + create"** → **"Create"**

### Step 4: Configure Messaging Endpoint

1. Go to your Azure Bot resource → **"Configuration"**
2. Under **"Messaging endpoint"**, enter your webhook URL:
   - Format: `https://your-domain.com/api/messages`
   - For testing with ngrok: `https://abc123.ngrok-free.app/api/messages`
3. Click **"Apply"**

### Step 5: Enable Teams Channel

1. In Azure Bot resource, go to **"Channels"**
2. Click **"Microsoft Teams"** icon
3. Review and accept Terms of Service
4. Click **"Apply"**
5. Teams channel status should show **"Running"**

## Phase 2: Teams App Manifest

### Create Manifest Files

You need 3 files in a directory:

#### 1. manifest.json

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.23/MicrosoftTeams.schema.json",
  "manifestVersion": "1.23",
  "version": "1.0.0",
  "id": "YOUR_APP_ID_HERE",
  "packageName": "com.yourcompany.openclawbot",
  "developer": {
    "name": "Your Company",
    "websiteUrl": "https://yourcompany.com",
    "privacyUrl": "https://yourcompany.com/privacy",
    "termsOfUseUrl": "https://yourcompany.com/terms"
  },
  "icons": {
    "color": "color.png",
    "outline": "outline.png"
  },
  "name": {
    "short": "OpenClaw",
    "full": "OpenClaw AI Assistant"
  },
  "description": {
    "short": "AI-powered automation assistant",
    "full": "OpenClaw is an AI assistant that helps with DevOps, development, and automation tasks."
  },
  "accentColor": "#2c3e50",
  "bots": [
    {
      "botId": "YOUR_APP_ID_HERE",
      "scopes": [
        "personal",
        "team",
        "groupchat"
      ],
      "supportsFiles": true,
      "isNotificationOnly": false
    }
  ],
  "permissions": [
    "identity",
    "messageTeamMembers"
  ],
  "validDomains": [
    "token.botframework.com"
  ],
  "webApplicationInfo": {
    "id": "YOUR_APP_ID_HERE",
    "resource": "api://botid-YOUR_APP_ID_HERE"
  },
  "authorization": {
    "permissions": {
      "resourceSpecific": [
        {
          "name": "ChannelMessage.Read.Group",
          "type": "Application"
        },
        {
          "name": "ChannelMessage.Send.Group",
          "type": "Application"
        },
        {
          "name": "ChatMessage.Read.Chat",
          "type": "Application"
        },
        {
          "name": "TeamMember.Read.Group",
          "type": "Application"
        },
        {
          "name": "Owner.Read.Group",
          "type": "Application"
        },
        {
          "name": "ChannelSettings.Read.Group",
          "type": "Application"
        },
        {
          "name": "TeamSettings.Read.Group",
          "type": "Application"
        }
      ]
    }
  }
}
```

**Replace `YOUR_APP_ID_HERE` with your actual Application (client) ID!**

#### 2. color.png
- Size: 192x192 pixels
- Full color icon for your bot

#### 3. outline.png
- Size: 32x32 pixels
- Monochrome outline icon

### Package the Manifest

```bash
# Create a ZIP containing all 3 files
zip -r openclaw-teams-app.zip manifest.json color.png outline.png
```

### Upload to Teams

1. Open Microsoft Teams
2. Click **"Apps"** in sidebar
3. Click **"Manage your apps"** → **"Upload an app"**
4. Click **"Upload a custom app"** → **"Upload for <your-org>"**
5. Select `openclaw-teams-app.zip`
6. Click **"Add"** to install

## Phase 3: OpenClaw Configuration

### Post-Deploy Enablement Script

If your Azure Bot already exists, you can enable Teams on an existing OpenClaw release with:

```bash
./setup-msteams-integration.sh
```

This script assumes:

- `ingress-nginx` is running in the cluster
- the shared ALB forwards `*.openclaw.dametech.net` traffic to `ingress-nginx`
- wildcard DNS for `*.openclaw.dametech.net` ultimately routes to your ingress entrypoint
- TLS/public exposure is handled separately outside this script
- you already have the Teams `appId`, `appPassword`, and `tenantId`

The script derives the public Teams endpoint from the release name:

```text
https://<release>.openclaw.dametech.net/api/messages
```

It then:

- copies the vendored local `plugins/msteams` source into the target pod and installs it via the OpenClaw CLI
- creates a Teams credentials secret for that release
- creates a release-specific NodePort service for the Teams webhook
- creates a release-specific `Ingress` routing `/api/messages` to that service
- patches `openclaw.json` to enable `channels.msteams`

### Install Teams Plugin

This repo vendors the Teams plugin source under [`plugins/msteams`](/mnt/c/projects/openclaw/plugins/msteams).
`setup-msteams-integration.sh` copies that folder into the target pod and runs:

```bash
openclaw plugins install /tmp/openclaw-msteams-source
```

This avoids the broken registry-based install path that was failing under ClawHub in the running pod.

### Configure openclaw.json

```json
{
  "channels": {
    "msteams": {
      "enabled": true,
      "appId": "00000000-0000-0000-0000-000000000000",
      "appPassword": "your-client-secret",
      "tenantId": "00000000-0000-0000-0000-000000000000",
      "webhook": {
        "port": 3978,
        "path": "/api/messages"
      },
      "dmPolicy": "open",
      "allowFrom": ["*"],
      "groupPolicy": "open"
    }
  }
}
```

**Use environment variables for secrets:**

```json
{
  "channels": {
    "msteams": {
      "enabled": true,
      "appId": "${MSTEAMS_APP_ID}",
      "appPassword": "${MSTEAMS_APP_PASSWORD}",
      "tenantId": "${MSTEAMS_TENANT_ID}",
      "webhook": {
        "port": 3978,
        "path": "/api/messages"
      },
      "dmPolicy": "open",
      "allowFrom": ["*"],
      "groupPolicy": "open"
    }
  }
}
```

## Phase 4: Kubernetes Deployment

### Option 1: Expose via Ingress (Production)

Create an Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: openclaw-teams-webhook
  namespace: openclaw
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - openclaw.yourdomain.com
      secretName: openclaw-teams-tls
  rules:
    - host: openclaw.yourdomain.com
      http:
        paths:
          - path: /api/messages
            pathType: Prefix
            backend:
              service:
                name: openclaw-teams-webhook
                port:
                  number: 3978
```

Update Helm values to expose port 3978:

```yaml
app-template:
  service:
    teams-webhook:
      controller: main
      ports:
        webhook:
          port: 3978
          targetPort: 3978
          protocol: TCP
```

### Option 2: ngrok for Testing

```bash
# Install ngrok
brew install ngrok  # macOS
# or download from https://ngrok.com

# Forward port 3978
kubectl port-forward -n openclaw svc/openclaw-teams-webhook 3978:3978 &

# Expose via ngrok
ngrok http 3978
```

Copy the ngrok URL (e.g., `https://abc123.ngrok-free.app`) and update Azure Bot messaging endpoint:
```
https://abc123.ngrok-free.app/api/messages
```

### Store Credentials in Kubernetes

```bash
export KUBECONFIG=~/.kube/au01-0.yaml

kubectl create secret generic openclaw-teams-credentials \
  --from-literal=MSTEAMS_APP_ID="YOUR_APP_ID" \
  --from-literal=MSTEAMS_APP_PASSWORD="YOUR_CLIENT_SECRET" \
  --from-literal=MSTEAMS_TENANT_ID="YOUR_TENANT_ID" \
  -n openclaw
```

Update Helm values to reference the secret:

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
                name: openclaw-teams-credentials
```

## Testing

### 1. Verify Webhook Endpoint

Test your public URL:
```bash
curl -X POST https://your-domain.com/api/messages \
  -H "Content-Type: application/json" \
  -d '{"type":"message","text":"test"}'
```

Should return 200 OK or validation response (not 404).

### 2. Send Message in Teams

1. Open Microsoft Teams
2. Find your bot in Apps
3. Send a DM: "Hello!"
4. Bot should respond (may require pairing approval)

### 3. Approve Pairing

```bash
# List pairing requests
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing list msteams

# Approve
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js pairing approve msteams <CODE>
```

### 4. Test in Channels

1. Add bot to a Teams channel
2. Mention it: `@OpenClaw hello`
3. Bot should respond

## Troubleshooting

### Bot Not Receiving Messages

**Check webhook connectivity:**
```bash
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main | grep -i "teams\|webhook"
```

**Verify Azure Bot endpoint:**
- Ensure messaging endpoint is correct
- Check Teams channel is enabled
- Test webhook URL is publicly accessible

### Authentication Errors

**Symptoms**: `401 Unauthorized` or `invalid_client`

**Solutions:**
- Verify App ID matches between Azure Bot and App Registration
- Check client secret hasn't expired
- Ensure tenant ID is correct
- Regenerate secret if needed

### Webhook 404 Errors

**Symptoms**: Azure Bot test shows 404

**Solutions:**
- Verify OpenClaw is listening on port 3978
- Check Ingress/ngrok is forwarding to correct port
- Ensure `/api/messages` path is correct
- Check firewall allows inbound traffic

## Advanced Configuration

### SharePoint Integration for Files

Enable file uploads in channels:

```json
{
  "channels": {
    "msteams": {
      "sharePointSiteId": "contoso.sharepoint.com,site-guid,web-guid",
      "fileUploadPath": "/OpenClawShared/"
    }
  }
}
```

Requires Graph API permissions:
- `Sites.ReadWrite.All`

### Per-Channel Configuration

```json
{
  "channels": {
    "msteams": {
      "teams": {
        "team-id-here": {
          "channels": {
            "channel-id-here": {
              "requireMention": true,
              "replyStyle": "thread",
              "enabled": true
            }
          }
        }
      }
    }
  }
}
```

### Access Control

```json
{
  "channels": {
    "msteams": {
      "dmPolicy": "open",
      "groupPolicy": "allowlist",
      "groupAllowFrom": ["user@company.com"],
      "allowFrom": ["*"]
    }
  }
}
```

## Security Best Practices

1. **Store credentials in 1Password** or Azure Key Vault
2. **Use TLS for webhooks** (Let's Encrypt with cert-manager)
3. **Validate webhook signatures** (Bot Framework signature validation)
4. **Use `dmPolicy: "open"`** when everyone in your tenant should be able to DM the bot directly
5. **Allowlist channels** for production
6. **Rotate client secrets** every 90 days
7. **Monitor audit logs** in Azure

## Next Steps

1. Create Azure Bot (tasks #11)
2. Expose webhook endpoint (task #12)
3. Deploy Teams integration (task #13)

---

**Sources:**
- [OpenClaw Teams Documentation](https://docs.openclaw.ai/channels/msteams)
- [Azure Bot Service Registration](https://learn.microsoft.com/en-us/azure/bot-service/bot-service-quickstart-registration)
- [Building Teams Bot 2026](https://medium.com/@shaamamanoharan/building-a-microsoft-teams-bot-using-fastapi-single-tenant-step-by-step-db79f30d9f29)
