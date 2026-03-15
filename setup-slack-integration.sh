#!/bin/bash
#
# OpenClaw Slack Integration Setup Script
# Automates Slack app configuration and deployment to Kubernetes
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}==>${NC} ${CYAN}$1${NC}\n"
}

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   OpenClaw Slack Integration Setup           ║"
    echo "║   Automated Configuration & Deployment       ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing=0

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        missing=1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found"
        missing=1
    fi

    if ! command -v op &> /dev/null; then
        log_warn "1Password CLI (op) not found - tokens will be stored in Kubernetes secrets only"
        USE_1PASSWORD=false
    else
        USE_1PASSWORD=true
        log_info "1Password CLI detected - will store tokens in vault"
    fi

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_PATH"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        log_error "Missing prerequisites. Please install required tools."
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Display manual steps for Slack app creation
show_slack_app_creation_steps() {
    log_step "Step 1: Create Slack App"

    cat <<EOF
${YELLOW}Manual Steps Required:${NC}

1. Go to: ${CYAN}https://api.slack.com/apps${NC}

2. Click ${CYAN}"Create New App"${NC} → ${CYAN}"From scratch"${NC}

3. App Name: ${CYAN}OpenClaw Bot${NC} (or your preferred name)
   Workspace: Select your workspace

4. ${BLUE}Configure Basic Information:${NC}
   - Under "App Home", enable "Messages Tab"
   - Optionally add bot display name and icon

5. ${BLUE}Enable Socket Mode:${NC}
   - Go to "Socket Mode" in sidebar
   - Toggle "Enable Socket Mode" to ON
   - Click "Generate" to create App-Level Token
   - Token Name: ${CYAN}openclaw-socket${NC}
   - Add scope: ${CYAN}connections:write${NC}
   - ${GREEN}Copy the App Token (xapp-...)${NC} - you'll need it next!

6. ${BLUE}Configure OAuth & Permissions:${NC}
   - Go to "OAuth & Permissions" in sidebar
   - Scroll to "Scopes" → "Bot Token Scopes"
   - Add these scopes:
     ${CYAN}• chat:write${NC}
     ${CYAN}• chat:write.customize${NC} (for custom bot identity)
     ${CYAN}• channels:history${NC}
     ${CYAN}• channels:read${NC}
     ${CYAN}• groups:history${NC}
     ${CYAN}• im:history${NC}
     ${CYAN}• im:read${NC}
     ${CYAN}• mpim:history${NC}
     ${CYAN}• mpim:read${NC}
     ${CYAN}• app_mentions:read${NC}
     ${CYAN}• reactions:read${NC}
     ${CYAN}• reactions:write${NC}
     ${CYAN}• pins:read${NC}
     ${CYAN}• pins:write${NC}
     ${CYAN}• emoji:read${NC}
     ${CYAN}• commands${NC}
     ${CYAN}• files:read${NC}
     ${CYAN}• files:write${NC}

7. ${BLUE}Install App to Workspace:${NC}
   - Scroll to top of "OAuth & Permissions"
   - Click ${CYAN}"Install to Workspace"${NC}
   - Authorize the app
   - ${GREEN}Copy the Bot User OAuth Token (xoxb-...)${NC}

8. ${BLUE}Subscribe to Bot Events:${NC}
   - Go to "Event Subscriptions" in sidebar
   - Toggle "Enable Events" to ON
   - Under "Subscribe to bot events", add:
     ${CYAN}• app_mention${NC}
     ${CYAN}• message.channels${NC}
     ${CYAN}• message.groups${NC}
     ${CYAN}• message.im${NC}
     ${CYAN}• message.mpim${NC}
     ${CYAN}• reaction_added${NC}
     ${CYAN}• reaction_removed${NC}
     ${CYAN}• member_joined_channel${NC}
     ${CYAN}• member_left_channel${NC}
     ${CYAN}• channel_rename${NC}
     ${CYAN}• pin_added${NC}
     ${CYAN}• pin_removed${NC}
   - Click "Save Changes"

${GREEN}When you have both tokens, return here and continue.${NC}

EOF

    read -p "Press Enter when you have copied both tokens..."
}

# Collect Slack tokens
collect_slack_tokens() {
    log_step "Step 2: Enter Slack Tokens"

    echo ""
    echo -n "Enter your Slack App Token (xapp-...): "
    read -r SLACK_APP_TOKEN

    if [[ ! $SLACK_APP_TOKEN =~ ^xapp- ]]; then
        log_error "Invalid App Token format. Should start with 'xapp-'"
        exit 1
    fi

    echo -n "Enter your Slack Bot Token (xoxb-...): "
    read -r SLACK_BOT_TOKEN

    if [[ ! $SLACK_BOT_TOKEN =~ ^xoxb- ]]; then
        log_error "Invalid Bot Token format. Should start with 'xoxb-'"
        exit 1
    fi

    log_info "Tokens collected successfully"
}

# Store tokens in 1Password
store_in_1password() {
    if [ "$USE_1PASSWORD" = false ]; then
        log_warn "Skipping 1Password storage (CLI not available)"
        return
    fi

    log_step "Step 3: Store Tokens in 1Password"

    echo ""
    echo -n "Enter 1Password vault name (default: openclaw): "
    read -r VAULT_NAME
    VAULT_NAME=${VAULT_NAME:-openclaw}

    log_info "Creating item in 1Password vault: $VAULT_NAME"

    # Check if item exists
    if op item get "OpenClaw Slack Tokens" --vault "$VAULT_NAME" &>/dev/null; then
        log_warn "Item 'OpenClaw Slack Tokens' already exists. Updating..."

        op item edit "OpenClaw Slack Tokens" \
            --vault "$VAULT_NAME" \
            "app_token[password]=$SLACK_APP_TOKEN" \
            "bot_token[password]=$SLACK_BOT_TOKEN" \
            > /dev/null

    else
        log_info "Creating new item..."

        op item create \
            --category=login \
            --title="OpenClaw Slack Tokens" \
            --vault="$VAULT_NAME" \
            "app_token[password]=$SLACK_APP_TOKEN" \
            "bot_token[password]=$SLACK_BOT_TOKEN" \
            "notes[text]=Slack integration tokens for OpenClaw bot" \
            > /dev/null
    fi

    log_info "Tokens stored in 1Password: op:///$VAULT_NAME/OpenClaw Slack Tokens/{app_token,bot_token}"

    # Set SecretRef paths
    APP_TOKEN_REF="op:///$VAULT_NAME/OpenClaw Slack Tokens/app_token"
    BOT_TOKEN_REF="op:///$VAULT_NAME/OpenClaw Slack Tokens/bot_token"
}

# Create or update Kubernetes secret
create_k8s_secret() {
    log_step "Step 4: Create Kubernetes Secret"

    export KUBECONFIG="$KUBECONFIG_PATH"

    if [ "$USE_1PASSWORD" = true ]; then
        log_info "Creating secret with 1Password references..."

        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-slack-tokens
  namespace: $NAMESPACE
  annotations:
    operator.1password.io/item-path: "$APP_TOKEN_REF"
    operator.1password.io/item-name: "OpenClaw Slack Tokens"
type: Opaque
stringData:
  SLACK_APP_TOKEN: "$APP_TOKEN_REF"
  SLACK_BOT_TOKEN: "$BOT_TOKEN_REF"
EOF

    else
        log_info "Creating secret with direct values..."

        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-slack-tokens
  namespace: $NAMESPACE
type: Opaque
stringData:
  SLACK_APP_TOKEN: "$SLACK_APP_TOKEN"
  SLACK_BOT_TOKEN: "$SLACK_BOT_TOKEN"
EOF

    fi

    log_info "Secret created: openclaw-slack-tokens"
}

# Generate openclaw.json configuration
generate_openclaw_config() {
    log_step "Step 5: Generate Configuration"

    log_info "Creating openclaw.json configuration snippet..."

    cat > /tmp/openclaw-slack-config.json <<'EOF'
{
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "appToken": "${SLACK_APP_TOKEN}",
      "botToken": "${SLACK_BOT_TOKEN}",
      "userAuth": {
        "mode": "allowlist"
      }
    }
  }
}
EOF

    log_info "Configuration created: /tmp/openclaw-slack-config.json"

    echo ""
    log_info "Configuration preview:"
    cat /tmp/openclaw-slack-config.json
    echo ""
}

# Update Helm values and deploy
update_helm_deployment() {
    log_step "Step 6: Update Helm Deployment"

    export KUBECONFIG="$KUBECONFIG_PATH"

    # Read current values
    if [ -f /tmp/openclaw-values.yaml ]; then
        log_info "Updating existing values file..."
        cp /tmp/openclaw-values.yaml /tmp/openclaw-values.yaml.bak
    else
        log_info "Creating new values file..."
        cat > /tmp/openclaw-values.yaml <<'EOF'
app-template:
  controllers:
    main:
      containers:
        main:
          args:
            - gateway
            - --bind
            - lan
            - --port
            - "18789"
          envFrom:
            - secretRef:
                name: openclaw-env-secret
            - secretRef:
                name: openclaw-slack-tokens

  configMaps:
    config:
      data:
        openclaw.json: |
          {
            "gateway": {
              "port": 18789,
              "mode": "local",
              "controlUi": {
                "dangerouslyAllowHostHeaderOriginFallback": true
              }
            },
            "channels": {
              "slack": {
                "enabled": true,
                "mode": "socket",
                "appToken": "${SLACK_APP_TOKEN}",
                "botToken": "${SLACK_BOT_TOKEN}",
                "userAuth": {
                  "mode": "allowlist"
                }
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
EOF
    fi

    log_info "Deploying updated configuration..."

    helm upgrade openclaw openclaw-community/openclaw \
        --namespace "$NAMESPACE" \
        --values /tmp/openclaw-values.yaml \
        --wait \
        --timeout 5m

    log_info "Deployment updated successfully"
}

# Wait for pod to be ready
wait_for_pod() {
    log_step "Step 7: Wait for Pod Ready"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Waiting for OpenClaw pod to be ready..."

    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=openclaw \
        -n "$NAMESPACE" \
        --timeout=300s

    log_info "Pod is ready!"
}

# Test Slack integration
test_slack_integration() {
    log_step "Step 8: Test Slack Integration"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Checking OpenClaw logs for Slack connection..."

    sleep 5

    kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -c main --tail=50 \
        | grep -i slack || log_warn "No Slack-related log entries found yet"

    echo ""
    log_info "To test the integration:"
    echo "  1. Open Slack and go to your workspace"
    echo "  2. Find the OpenClaw bot in the Apps section"
    echo "  3. Send a direct message to the bot"
    echo "  4. The bot should respond (after pairing approval)"
    echo ""
    echo "  To approve pairing (if needed), run:"
    echo "  ${CYAN}kubectl exec -n openclaw deployment/openclaw -c main -- node dist/index.js pairing list${NC}"
    echo "  ${CYAN}kubectl exec -n openclaw deployment/openclaw -c main -- node dist/index.js pairing approve slack <code>${NC}"
    echo ""
}

# Show completion summary
show_completion() {
    log_step "✅ Setup Complete!"

    cat <<EOF

${GREEN}Slack integration is now configured and deployed!${NC}

${BLUE}Next Steps:${NC}

1. ${CYAN}Test the Bot:${NC}
   - Open Slack and find your OpenClaw bot
   - Send it a DM: "Hello!"

2. ${CYAN}Approve Pairing (if needed):${NC}
   kubectl exec -n openclaw deployment/openclaw -c main -- \\
     node dist/index.js pairing approve slack <code>

3. ${CYAN}Invite Bot to Channels:${NC}
   - Type ${CYAN}/invite @OpenClaw${NC} in any channel
   - Mention bot with ${CYAN}@OpenClaw${NC} to get responses

4. ${CYAN}View Logs:${NC}
   kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main -f

${BLUE}Configuration Files:${NC}
- Kubernetes Secret: ${CYAN}openclaw-slack-tokens${NC}
- Helm Values: ${CYAN}/tmp/openclaw-values.yaml${NC}
- Config Snippet: ${CYAN}/tmp/openclaw-slack-config.json${NC}

${BLUE}Tokens Stored:${NC}
EOF

    if [ "$USE_1PASSWORD" = true ]; then
        echo "- 1Password: ${CYAN}$VAULT_NAME/OpenClaw Slack Tokens${NC}"
    fi
    echo "- Kubernetes: ${CYAN}$NAMESPACE/openclaw-slack-tokens${NC}"

    echo ""
    log_info "Documentation: https://docs.openclaw.ai/channels/slack"
    echo ""
}

# Main execution
main() {
    show_banner
    check_prerequisites
    show_slack_app_creation_steps
    collect_slack_tokens
    store_in_1password
    create_k8s_secret
    generate_openclaw_config
    update_helm_deployment
    wait_for_pod
    test_slack_integration
    show_completion
}

# Run main function
main
