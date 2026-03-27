#!/bin/bash
#
# OpenClaw Port Forward Script
# Establishes port forwarding to access OpenClaw web interface
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
RELEASE_NAME="openclaw"
LOCAL_PORT="18789"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Establishes port forwarding to access the OpenClaw web interface."
    echo ""
    echo "Options:"
    echo "  -p, --port PORT    Local port to forward to (default: 18789)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Use default port 18789"
    echo "  $0 -p 8080         # Forward to localhost:8080"
    echo "  $0 --port 9000     # Forward to localhost:9000"
    echo ""
}

get_release_name() {
    local input_name

    echo ""
    echo -n "Enter instance name [openclaw]: "
    read -r input_name

    if [ -n "$input_name" ]; then
        RELEASE_NAME="$input_name"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            LOCAL_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            # Support legacy positional argument
            if [[ $1 =~ ^[0-9]+$ ]]; then
                LOCAL_PORT="$1"
                shift
            else
                echo "Error: Unknown option $1"
                echo ""
                show_usage
                exit 1
            fi
            ;;
    esac
done

# Validate port number
if ! [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || [ "$LOCAL_PORT" -lt 1 ] || [ "$LOCAL_PORT" -gt 65535 ]; then
    echo "Error: Invalid port number '$LOCAL_PORT'. Must be between 1 and 65535."
    exit 1
fi

get_release_name

# Export kubeconfig
export KUBECONFIG="$KUBECONFIG_PATH"

# Check if pod is running
log_info "Checking OpenClaw pod status..."
if ! kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" | grep -q "Running"; then
    log_warn "OpenClaw pod is not running. Deploy it first with ./openclaw-deploy.sh"
    exit 1
fi

# Get gateway token
log_info "Retrieving gateway token..."
GATEWAY_TOKEN=$(kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -o '"token": "[^"]*"' | cut -d'"' -f4)

echo ""
echo "============================================"
log_info "Starting port forward to OpenClaw..."
echo "============================================"
echo ""
echo -e "${BLUE}Gateway Token:${NC} $GATEWAY_TOKEN"
echo -e "${BLUE}Web Interface:${NC} http://localhost:$LOCAL_PORT"
echo -e "${BLUE}Remote Port:${NC}   18789 (in pod)"
echo -e "${BLUE}Local Port:${NC}    $LOCAL_PORT"
echo ""
echo "Press Ctrl+C to stop port forwarding"
echo ""

# Start port forwarding
kubectl port-forward -n "$NAMESPACE" "svc/$RELEASE_NAME" "$LOCAL_PORT:18789"
