#!/bin/bash
#
# OpenClaw Cleanup Script
# Removes OpenClaw deployment from Kubernetes cluster
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
RELEASE_NAME="openclaw"

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

# Confirm deletion
confirm_deletion() {
    echo ""
    log_warn "This will delete the OpenClaw deployment and all associated resources."
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r response

    if [ "$response" != "yes" ]; then
        log_info "Deletion cancelled."
        exit 0
    fi
}

# Check if deployment exists
check_deployment() {
    export KUBECONFIG="$KUBECONFIG_PATH"

    if ! helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$RELEASE_NAME"; then
        log_warn "OpenClaw deployment not found in namespace '$NAMESPACE'"
        exit 0
    fi
}

# Delete Helm release
delete_release() {
    log_info "Deleting Helm release '$RELEASE_NAME'..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
}

# Delete PVC (optional)
delete_pvc() {
    echo ""
    echo -n "Delete PersistentVolumeClaim (this will delete all data)? (yes/no): "
    read -r response

    if [ "$response" = "yes" ]; then
        log_info "Deleting PersistentVolumeClaim..."
        export KUBECONFIG="$KUBECONFIG_PATH"
        kubectl delete pvc -n "$NAMESPACE" --all
    else
        log_info "PVC preserved. Data will be retained for next deployment."
    fi
}

# Delete namespace (optional)
delete_namespace() {
    echo ""
    echo -n "Delete namespace '$NAMESPACE' (removes all resources including secrets)? (yes/no): "
    read -r response

    if [ "$response" = "yes" ]; then
        log_info "Deleting namespace '$NAMESPACE'..."
        export KUBECONFIG="$KUBECONFIG_PATH"
        kubectl delete namespace "$NAMESPACE"
    else
        log_info "Namespace preserved."
    fi
}

# Stop port-forward processes
stop_port_forward() {
    log_info "Stopping any running port-forward processes..."

    pkill -f "kubectl port-forward.*openclaw" || true
}

# Main execution
main() {
    log_info "Starting OpenClaw cleanup..."

    confirm_deletion
    check_deployment
    stop_port_forward
    delete_release
    delete_pvc
    delete_namespace

    echo ""
    log_info "Cleanup complete! 🦞"
}

# Run main function
main
