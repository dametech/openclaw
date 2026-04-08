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

# Prompt for release name
get_release_name() {
    local input_name

    echo ""
    echo -n "Enter instance name [openclaw]: "
    read -r input_name

    if [ -n "$input_name" ]; then
        RELEASE_NAME="$input_name"
    fi

    if [ -z "$RELEASE_NAME" ]; then
        log_error "Instance name cannot be empty."
        exit 1
    fi
}

# Confirm deletion
confirm_deletion() {
    echo ""
    log_warn "This will delete the OpenClaw deployment '$RELEASE_NAME' and associated resources."
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

# Delete PVCs for the release
delete_pvc() {
    log_info "Deleting PersistentVolumeClaim(s) for release '$RELEASE_NAME'..."
    export KUBECONFIG="$KUBECONFIG_PATH"
    local pvc_names
    local pvc_name
    pvc_names=$(kubectl get pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o name 2>/dev/null || true)

    if [ -z "$pvc_names" ]; then
        log_warn "No PVCs found for release '$RELEASE_NAME'."
        return
    fi

    kubectl delete -n "$NAMESPACE" $pvc_names

    for pvc_name in $pvc_names; do
        kubectl wait --for=delete "$pvc_name" -n "$NAMESPACE" --timeout=180s || true
    done
}

delete_configmaps() {
    log_info "Deleting ConfigMap(s) for release '$RELEASE_NAME'..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-config" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-scripts" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-startup-script" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-ms-graph-plugin" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-jira-plugin" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-pod-delegate-plugin" --ignore-not-found
}

# Stop port-forward processes
stop_port_forward() {
    log_info "Stopping any running port-forward processes..."

    pkill -f "kubectl port-forward.*$RELEASE_NAME" || true
}

# Main execution
main() {
    log_info "Starting OpenClaw cleanup..."

    get_release_name
    confirm_deletion
    check_deployment
    stop_port_forward
    delete_release
    delete_configmaps
    delete_pvc

    echo ""
    log_info "Cleanup complete! 🦞"
}

# Run main function
main
