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

# Create reference files for easy copying
create_reference_files() {
    log_info "Creating reference files for easy copying..."

    # Create scopes file
    cat > /tmp/slack-bot-scopes.txt <<'EOF'
chat:write
chat:write.customize
channels:history
channels:read
groups:history
im:history
im:read
mpim:history
mpim:read
app_mentions:read
reactions:read
reactions:write
pins:read
pins:write
emoji:read
commands
files:read
files:write
EOF

    # Create events file
    cat > /tmp/slack-bot-events.txt <<'EOF'
app_mention
message.channels
message.groups
message.im
message.mpim
reaction_added
reaction_removed
member_joined_channel
member_left_channel
channel_rename
pin_added
pin_removed
EOF

    log_info "Reference files created:"
    echo "  📄 OAuth Scopes: /tmp/slack-bot-scopes.txt"
    echo "  📄 Bot Events: /tmp/slack-bot-events.txt"
    echo ""
}

# Ask user for setup method
choose_setup_method() {
    log_step "Choose Setup Method"

    cat <<'EOF'

Choose how you want to create your Slack app:

  1) App Manifest (Recommended) - One paste, fully configured
  2) Manual Setup - Step-by-step through Slack UI

EOF

    read -p "Enter choice (1 or 2): " choice

    case $choice in
        1)
            SETUP_METHOD="manifest"
            ;;
        2)
            SETUP_METHOD="manual"
            ;;
        *)
            log_error "Invalid choice. Please enter 1 or 2"
            exit 1
            ;;
    esac
}

# Show manifest-based setup
show_manifest_setup() {
    log_step "Step 1: Create App with Manifest"

    create_reference_files

    # Check if manifest file exists
    if [ ! -f "$SCRIPT_DIR/slack-app-manifest.yaml" ]; then
        log_error "Manifest file not found: $SCRIPT_DIR/slack-app-manifest.yaml"
        exit 1
    fi

    # Try to open URL in browser
    echo ""
    log_info "Opening Slack API page in your browser..."
    if command -v open &> /dev/null; then
        open "https://api.slack.com/apps" 2>/dev/null && echo "  ✓ Browser opened" || echo "  ⚠ Please open manually"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "https://api.slack.com/apps" 2>/dev/null && echo "  ✓ Browser opened" || echo "  ⚠ Please open manually"
    else
        echo "  ⚠ Please open this URL: https://api.slack.com/apps"
    fi

    sleep 2
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    cat <<'EOF'
📋 QUICK SETUP WITH APP MANIFEST

This method creates a fully configured Slack app in seconds!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📱 STEP 1: Create App from Manifest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   🌐 URL: https://api.slack.com/apps

   1. Click "Create New App"
   2. Select "From an app manifest"
   3. Choose your workspace
   4. Click "Next"
   5. Select "YAML" tab
   6. Copy the manifest below and paste it in
   7. Click "Next"
   8. Review the configuration
   9. Click "Create"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 APP MANIFEST (copy everything below):

EOF

    # Display manifest with copy helper
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$SCRIPT_DIR/slack-app-manifest.yaml"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cat <<EOF

   📋 Quick copy to clipboard:

      pbcopy < $SCRIPT_DIR/slack-app-manifest.yaml           (macOS)
      xclip -sel clip < $SCRIPT_DIR/slack-app-manifest.yaml  (Linux)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔌 STEP 2: Generate Socket Mode Token
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   After creating the app:

   1. In the sidebar, click "Socket Mode"
   2. A token generation dialog should appear automatically
   3. If not, click "Generate"
   4. Token Name: openclaw-socket
   5. The scope "connections:write" is already configured
   6. Click "Generate"
   7. ✅ COPY THE APP TOKEN (starts with xapp-)
   8. Click "Done"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 STEP 3: Install App to Workspace
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. In the sidebar, click "Install App"
   2. Click "Install to Workspace"
   3. Review permissions (already configured by manifest)
   4. Click "Allow"
   5. ✅ COPY THE BOT USER OAUTH TOKEN (starts with xoxb-)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ That's it! The manifest configured everything else:
   ✓ OAuth scopes (18 scopes)
   ✓ Bot events (12 events)
   ✓ Socket Mode enabled
   ✓ Messages Tab enabled
   ✓ App home configured

When you have BOTH tokens (xapp-... and xoxb-...), press Enter to continue...
EOF

    read -p ""
}

# Display manual steps for Slack app creation
show_manual_setup() {
    log_step "Step 1: Create and Configure Slack App"

    create_reference_files

    # Try to open URL in browser
    echo ""
    log_info "Opening Slack API page in your browser..."
    if command -v open &> /dev/null; then
        open "https://api.slack.com/apps" 2>/dev/null && echo "  ✓ Browser opened" || echo "  ⚠ Please open manually"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "https://api.slack.com/apps" 2>/dev/null && echo "  ✓ Browser opened" || echo "  ⚠ Please open manually"
    else
        echo "  ⚠ Please open this URL: https://api.slack.com/apps"
    fi

    sleep 2
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    cat <<'EOF'
📋 SLACK APP SETUP INSTRUCTIONS

⚠️  CRITICAL: This is a TWO-PHASE setup!
   Phase 1: Create app and install (get initial tokens)
   Phase 2: Add events and REINSTALL (events won't work without reinstall!)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 1: INITIAL SETUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📱 STEP 1: Create the Slack App
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   🌐 URL: https://api.slack.com/apps

   1. Click "Create New App"
   2. Select "From scratch"
   3. App Name: OpenClaw Bot
   4. Choose your workspace
   5. Click "Create App"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔌 STEP 2: Enable Socket Mode (DO THIS FIRST!)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   ⚠️  IMPORTANT: Enable Socket Mode BEFORE adding scopes!
      This lets you skip Request URLs for events later.

   1. In the sidebar, click "Socket Mode"
   2. Toggle "Enable Socket Mode" to ON
   3. A dialog appears - click "Generate"
   4. Token Name: openclaw-socket
   5. Add scope: connections:write
   6. Click "Generate"
   7. ✅ COPY THE APP TOKEN (starts with xapp-...)
      Save this token - you'll need it at the end!
   8. Click "Done"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔐 STEP 3: Add OAuth Scopes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. In the sidebar, click "OAuth & Permissions"
   2. Scroll down to "Scopes" section
   3. Under "Bot Token Scopes", click "Add an OAuth Scope"
   4. Add each scope from the list below

   📋 Easy copy method:

      In a new terminal window, run:

      cat /tmp/slack-bot-scopes.txt

      Or copy to clipboard:

      pbcopy < /tmp/slack-bot-scopes.txt           (macOS)
      xclip -sel clip < /tmp/slack-bot-scopes.txt  (Linux)

   📝 Scopes to add (18 total):

EOF

    # Display scopes in a clean format
    while IFS= read -r scope; do
        echo "      • $scope"
    done < /tmp/slack-bot-scopes.txt

    cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 STEP 4: Install App to Workspace
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. Scroll to the top of the "OAuth & Permissions" page
   2. Click "Install to Workspace" button
   3. Review permissions
   4. Click "Allow"
   5. ✅ COPY THE BOT USER OAUTH TOKEN (starts with xoxb-)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 STEP 4: Install App to Workspace (FIRST TIME)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. In the sidebar, click "OAuth & Permissions"
   2. Scroll to top and click "Install to Workspace"
   3. Review permissions
   4. Click "Allow"
   5. ✅ COPY THE BOT USER OAUTH TOKEN (starts with xoxb-...)
      Save this token - you'll need it at the end!

   ⚠️  DON'T CLOSE THE BROWSER YET! We need to add events next!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 2: ADD EVENTS (CRITICAL!)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📡 STEP 5: Subscribe to Bot Events
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   ⚠️  CRITICAL: Without these events, the bot won't receive messages!

   1. In the sidebar, click "Event Subscriptions"
   2. Toggle "Enable Events" to ON
   3. You should see: "Socket mode is enabled. You don't need a request URL."
   4. Scroll down to "Subscribe to bot events"
   5. Click "Add Bot User Event"
   6. Add EACH event from the list below (5 events total)

   📋 Easy copy method:

      cat /tmp/slack-bot-events.txt

   📝 Events to add (12 total):

EOF

    # Display events in a clean format
    while IFS= read -r event; do
        echo "      • $event"
    done < /tmp/slack-bot-events.txt

    cat <<'EOF'

   6. Click "Save Changes" at the bottom

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💬 STEP 6: Enable Messages Tab
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. In the sidebar, click "App Home"
   2. Under "Show Tabs", toggle "Messages Tab" to ON
   3. Enable "Allow users to send Slash commands and messages"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ You should now have TWO tokens:
   • App Token (xapp-...) from Socket Mode
   • Bot Token (xoxb-...) from OAuth installation

EOF

    echo ""
    read -p "Press Enter when you have both tokens ready... "
}

# Collect Slack tokens
collect_slack_tokens() {
    log_step "Step 2: Enter Slack Tokens"

    echo ""
    echo "Please paste your tokens below:"
    echo ""

    echo -n "App Token (xapp-...): "
    read -r SLACK_APP_TOKEN

    if [[ ! $SLACK_APP_TOKEN =~ ^xapp- ]]; then
        log_error "Invalid App Token format. Should start with 'xapp-'"
        exit 1
    fi

    echo -n "Bot Token (xoxb-...): "
    read -r SLACK_BOT_TOKEN

    if [[ ! $SLACK_BOT_TOKEN =~ ^xoxb- ]]; then
        log_error "Invalid Bot Token format. Should start with 'xoxb-'"
        exit 1
    fi

    echo ""
    log_info "✓ Tokens validated successfully"
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

    log_info "Storing tokens in 1Password vault: $VAULT_NAME"

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

    log_info "✓ Tokens stored in 1Password"
    echo "  📍 Location: op:///$VAULT_NAME/OpenClaw Slack Tokens"

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

    log_info "✓ Secret created: openclaw-slack-tokens"
}

# Generate openclaw.json configuration
generate_openclaw_config() {
    log_step "Step 5: Generate Configuration"

    log_info "Creating openclaw.json configuration..."

    cat > /tmp/openclaw-slack-config.json <<'EOF'
{
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "appToken": "${SLACK_APP_TOKEN}",
      "botToken": "${SLACK_BOT_TOKEN}"
    }
  }
}
EOF

    log_info "✓ Configuration created: /tmp/openclaw-slack-config.json"
}

# Update Helm values and deploy
update_helm_deployment() {
    log_step "Step 6: Update Helm Deployment"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Creating Helm values file..."

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
                "botToken": "${SLACK_BOT_TOKEN}"
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

    log_info "Deploying updated configuration to Kubernetes..."

    helm upgrade openclaw openclaw-community/openclaw \
        --namespace "$NAMESPACE" \
        --values /tmp/openclaw-values.yaml \
        --wait \
        --timeout 5m

    log_info "✓ Deployment updated successfully"
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

    log_info "✓ Pod is ready!"
}

# Test Slack integration
test_slack_integration() {
    log_step "Step 8: Verify Slack Integration"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Checking OpenClaw logs for Slack connection..."

    sleep 5

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Recent logs:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -c main --tail=30 \
        | grep -i "slack\|socket\|channel" || log_warn "No Slack-related log entries found yet"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Show completion summary
show_completion() {
    log_step "✅ Setup Complete!"

    cat <<EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}   Slack Integration Successfully Configured!${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${BLUE}📱 Test the Bot:${NC}

   1. Open Slack workspace
   2. Go to "Apps" section
   3. Find "OpenClaw Bot"
   4. Send a DM: "Hello!"

${BLUE}🔐 Approve Pairing (if needed):${NC}

   kubectl exec -n openclaw deployment/openclaw -c main -- \\
     node dist/index.js pairing list

   kubectl exec -n openclaw deployment/openclaw -c main -- \\
     node dist/index.js pairing approve slack <code>

${BLUE}💬 Invite to Channels:${NC}

   In any channel, type:
   /invite @OpenClaw

   Then mention the bot:
   @OpenClaw what can you help me with?

${BLUE}📊 View Logs:${NC}

   kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main -f

${BLUE}📄 Configuration Files:${NC}

   • Kubernetes Secret: ${CYAN}openclaw-slack-tokens${NC}
   • Helm Values: ${CYAN}/tmp/openclaw-values.yaml${NC}
   • Config Snippet: ${CYAN}/tmp/openclaw-slack-config.json${NC}
   • OAuth Scopes: ${CYAN}/tmp/slack-bot-scopes.txt${NC}
   • Bot Events: ${CYAN}/tmp/slack-bot-events.txt${NC}

${BLUE}🔑 Tokens Stored In:${NC}

EOF

    if [ "$USE_1PASSWORD" = true ]; then
        echo "   • 1Password: ${CYAN}$VAULT_NAME/OpenClaw Slack Tokens${NC}"
    fi
    echo "   • Kubernetes: ${CYAN}$NAMESPACE/openclaw-slack-tokens${NC}"

    cat <<EOF

${BLUE}📚 Documentation:${NC}

   https://docs.openclaw.ai/channels/slack

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF
}

# Main execution
main() {
    show_banner
    check_prerequisites
    choose_setup_method

    if [ "$SETUP_METHOD" = "manifest" ]; then
        show_manifest_setup
    else
        show_manual_setup
    fi

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
