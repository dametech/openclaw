#!/bin/bash
#
# OpenClaw Port Forward Script
# Establishes port forwarding to access OpenClaw web interface
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
LOCAL_PORT="${1:-18789}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Export kubeconfig
export KUBECONFIG="$KUBECONFIG_PATH"

# Check if pod is running
log_info "Checking OpenClaw pod status..."
if ! kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw | grep -q "Running"; then
    log_warn "OpenClaw pod is not running. Deploy it first with ./openclaw-deploy.sh"
    exit 1
fi

# Get gateway token
log_info "Retrieving gateway token..."
GATEWAY_TOKEN=$(kubectl exec -n "$NAMESPACE" deployment/openclaw -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -o '"token": "[^"]*"' | cut -d'"' -f4)

echo ""
echo "============================================"
log_info "Starting port forward to OpenClaw..."
echo "============================================"
echo ""
echo "Gateway Token: $GATEWAY_TOKEN"
echo "Web Interface: http://localhost:$LOCAL_PORT"
echo ""
echo "Press Ctrl+C to stop port forwarding"
echo ""

# Start port forwarding
kubectl port-forward -n "$NAMESPACE" svc/openclaw "$LOCAL_PORT:18789"
