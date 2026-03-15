#!/bin/bash
#
# OpenClaw Deployment Script for Kubernetes
# Deploys OpenClaw AI assistant to au01-0 cluster
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
RELEASE_NAME="openclaw"
HELM_REPO="openclaw-community"
HELM_REPO_URL="https://serhanekicii.github.io/openclaw-helm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install Helm."
        exit 1
    fi

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_PATH"
        exit 1
    fi

    log_info "Prerequisites check passed."
}

# Prompt for API key
get_api_key() {
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        log_info "Using ANTHROPIC_API_KEY from environment"
        API_KEY="$ANTHROPIC_API_KEY"
    else
        echo ""
        echo -n "Enter your Anthropic API key (sk-ant-...): "
        read -r API_KEY

        if [[ ! $API_KEY =~ ^sk-ant- ]]; then
            log_error "Invalid API key format. Should start with 'sk-ant-'"
            exit 1
        fi
    fi
}

# Setup Helm repository
setup_helm_repo() {
    log_info "Setting up Helm repository..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    if helm repo list | grep -q "$HELM_REPO"; then
        log_info "Helm repo already exists, updating..."
        helm repo update
    else
        log_info "Adding Helm repository..."
        helm repo add "$HELM_REPO" "$HELM_REPO_URL"
        helm repo update
    fi
}

# Create namespace
create_namespace() {
    log_info "Creating namespace '$NAMESPACE'..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

# Create API key secret
create_secret() {
    log_info "Creating API key secret..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-env-secret
  namespace: $NAMESPACE
type: Opaque
stringData:
  ANTHROPIC_API_KEY: "$API_KEY"
EOF
}

# Create values file
create_values() {
    log_info "Creating Helm values file..."

    cat > /tmp/openclaw-values.yaml <<'EOF'
app-template:
  controllers:
    main:
      containers:
        main:
          # Use loopback binding for security (access via port-forward)
          args:
            - gateway
            - --bind
            - loopback
            - --port
            - "18789"
          # Reference the secret containing the Anthropic API key
          envFrom:
            - secretRef:
                name: openclaw-env-secret

  # Use the Talos hostpath storage class
  persistence:
    data:
      enabled: true
      type: persistentVolumeClaim
      accessMode: ReadWriteOnce
      size: 5Gi
      storageClass: talos-hostpath
EOF
}

# Deploy OpenClaw
deploy_openclaw() {
    log_info "Deploying OpenClaw..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        log_warn "OpenClaw is already installed. Upgrading..."
        helm upgrade "$RELEASE_NAME" "$HELM_REPO/openclaw" \
            --namespace "$NAMESPACE" \
            --values /tmp/openclaw-values.yaml \
            --wait \
            --timeout 10m
    else
        helm install "$RELEASE_NAME" "$HELM_REPO/openclaw" \
            --namespace "$NAMESPACE" \
            --values /tmp/openclaw-values.yaml \
            --wait \
            --timeout 10m
    fi
}

# Get gateway token
get_gateway_token() {
    log_info "Retrieving gateway token..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    # Wait for pod to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=openclaw -n "$NAMESPACE" --timeout=300s || true

    sleep 5

    GATEWAY_TOKEN=$(kubectl exec -n "$NAMESPACE" deployment/openclaw -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -o '"token": "[^"]*"' | cut -d'"' -f4)

    if [ -n "$GATEWAY_TOKEN" ]; then
        echo ""
        log_info "Gateway Token: $GATEWAY_TOKEN"
        echo ""
    else
        log_warn "Could not retrieve gateway token. Check logs after deployment."
    fi
}

# Display access instructions
show_access_info() {
    echo ""
    echo "============================================"
    log_info "OpenClaw deployed successfully! 🦞"
    echo "============================================"
    echo ""
    echo "To access OpenClaw:"
    echo "1. Start port forwarding:"
    echo "   export KUBECONFIG=$KUBECONFIG_PATH"
    echo "   kubectl port-forward -n $NAMESPACE svc/openclaw 18789:18789"
    echo ""
    echo "2. Open in browser: http://localhost:18789"
    echo "3. Authenticate with the gateway token shown above"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=openclaw -c main -f"
    echo ""
}

# Main execution
main() {
    log_info "Starting OpenClaw deployment..."

    check_prerequisites
    get_api_key
    setup_helm_repo
    create_namespace
    create_secret
    create_values
    deploy_openclaw
    get_gateway_token
    show_access_info
}

# Run main function
main
