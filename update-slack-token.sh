#!/bin/bash
#
# Update Slack Token in OpenClaw Pod
# Quick script to update tokens without full redeployment
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Updates Slack tokens in the OpenClaw pod configuration.

Options:
  -a, --app-token TOKEN    Slack App Token (xapp-...)
  -b, --bot-token TOKEN    Slack Bot Token (xoxb-...)
  -h, --help               Show this help

Examples:
  $0 -a xapp-... -b xoxb-...
  $0 --app-token xapp-... --bot-token xoxb-...

Interactive mode (no arguments):
  $0

When to use this:
  - After reinstalling Slack app (generates new bot token)
  - After adding/removing OAuth scopes (requires reinstall)
  - When rotating tokens for security

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app-token)
            APP_TOKEN="$2"
            shift 2
            ;;
        -b|--bot-token)
            BOT_TOKEN="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Interactive mode if no tokens provided
if [ -z "$APP_TOKEN" ] || [ -z "$BOT_TOKEN" ]; then
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   OpenClaw Slack Token Update                ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""

    if [ -z "$APP_TOKEN" ]; then
        echo -n "Enter Slack App Token (xapp-...): "
        read -r APP_TOKEN
    fi

    if [ -z "$BOT_TOKEN" ]; then
        echo -n "Enter Slack Bot Token (xoxb-...): "
        read -r BOT_TOKEN
    fi
fi

# Validate tokens
if [[ ! $APP_TOKEN =~ ^xapp- ]]; then
    log_error "Invalid App Token. Must start with 'xapp-'"
    exit 1
fi

if [[ ! $BOT_TOKEN =~ ^xoxb- ]]; then
    log_error "Invalid Bot Token. Must start with 'xoxb-'"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Check pod exists
log_info "Checking OpenClaw pod..."
if ! kubectl get deployment openclaw -n "$NAMESPACE" &>/dev/null; then
    log_error "OpenClaw deployment not found in namespace $NAMESPACE"
    exit 1
fi

# Get current config
log_info "Reading current configuration..."
kubectl exec -n "$NAMESPACE" deployment/openclaw -c main -- \
  cat /home/node/.openclaw/openclaw.json > /tmp/openclaw-current.json

if [ ! -f /tmp/openclaw-current.json ]; then
    log_error "Failed to read current configuration"
    exit 1
fi

# Update tokens
log_info "Updating Slack tokens..."
cat /tmp/openclaw-current.json | \
  jq ".channels.slack.appToken = \"$APP_TOKEN\"" | \
  jq ".channels.slack.botToken = \"$BOT_TOKEN\"" | \
  jq ".channels.slack.enabled = true" | \
  jq ".channels.slack.mode = \"socket\"" | \
  jq ".channels.slack.groupPolicy = \"open\"" \
  > /tmp/openclaw-updated.json

# Verify update
if ! jq -e .channels.slack /tmp/openclaw-updated.json &>/dev/null; then
    log_error "Failed to update configuration"
    exit 1
fi

log_info "Updated configuration:"
jq .channels.slack /tmp/openclaw-updated.json

# Write back to pod
log_info "Writing configuration to pod..."
kubectl exec -n "$NAMESPACE" deployment/openclaw -c main -i -- \
  sh -c 'cat > /home/node/.openclaw/openclaw.json' < /tmp/openclaw-updated.json

# Restart pod
log_info "Restarting OpenClaw pod..."
kubectl rollout restart deployment/openclaw -n "$NAMESPACE"

# Wait for ready
log_info "Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=openclaw \
  -n "$NAMESPACE" \
  --timeout=120s

# Check connection
log_info "Verifying Slack connection..."
sleep 5
kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -c main --tail=20 \
  | grep -i "slack.*connected" || log_warn "Connection not confirmed in logs yet"

echo ""
log_info "✅ Slack tokens updated successfully!"
echo ""
echo "Next steps:"
echo "  1. Send a message to @claw in Slack"
echo "  2. If pairing is needed, run:"
echo "     kubectl exec -n $NAMESPACE deployment/openclaw -c main -- \\"
echo "       node dist/index.js pairing approve slack <CODE>"
echo ""
echo "View logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=openclaw -c main -f"
echo ""
