#!/bin/bash
#
# Ollama Embeddings Deployment Script for Kubernetes
# Deploys a cluster-internal Ollama pod for OpenClaw semantic memory embeddings
#

set -e

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="${NAMESPACE:-openclaw}"
OLLAMA_EMBEDDINGS_MODEL="${OLLAMA_EMBEDDINGS_MODEL:-nomic-embed-text}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_PATH"
        exit 1
    fi
}

create_namespace() {
    export KUBECONFIG="$KUBECONFIG_PATH"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

render_template() {
    local template_file="$1"

    sed \
        -e "s|\${NAMESPACE}|$(escape_sed_replacement "$NAMESPACE")|g" \
        -e "s|\${OLLAMA_EMBEDDINGS_MODEL}|$(escape_sed_replacement "$OLLAMA_EMBEDDINGS_MODEL")|g" \
        "$template_file"
}

apply_resources() {
    local template_file

    log_info "Applying Ollama embeddings resources..."
    export KUBECONFIG="$KUBECONFIG_PATH"

    for template_file in \
        k8s/ollama-embeddings-deployment.yaml \
        k8s/ollama-embeddings-service.yaml \
        k8s/ollama-embeddings-networkpolicy.yaml; do
        kubectl apply -f <(render_template "$template_file")
    done
}

show_access_info() {
    echo ""
    log_info "Ollama embeddings deployed."
    echo "Service DNS: http://ollama-embeddings.${NAMESPACE}.svc.cluster.local:11434"
    echo "Model: ${OLLAMA_EMBEDDINGS_MODEL}"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get deploy,svc,networkpolicy -n ${NAMESPACE} | grep ollama-embeddings"
    echo "  kubectl logs -n ${NAMESPACE} deployment/ollama-embeddings"
    echo ""
}

main() {
    check_prerequisites
    create_namespace
    apply_resources
    show_access_info
}

main
