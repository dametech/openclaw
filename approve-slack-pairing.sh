#!/bin/bash
#
# Approve Slack pairing for an OpenClaw deployment
#

set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
RELEASE_NAME="openclaw"
PAIRING_CODE=""
LIST_PAIRINGS=false

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

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Lists pending Slack pairings for an OpenClaw deployment and optionally approves one.

Options:
  -r, --release NAME      Release name
  -n, --namespace NAME    Namespace (default: openclaw)
  -k, --kubeconfig PATH   Kubeconfig path (default: \$HOME/.kube/au01-0.yaml)
  -c, --code CODE         Slack pairing code to approve
  --list                  List pending Slack pairings before prompting for a code
  -h, --help              Show this help message

Examples:
  $0 --release oc-marc
  $0 --release oc-marc --code ABC123
  $0 --release oc-marc --list
EOF
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

check_prerequisites() {
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found"
        exit 1
    fi

    if ! command -v timeout >/dev/null 2>&1; then
        log_error "timeout not found"
        exit 1
    fi
}

list_pairings() {
    log_info "Listing pending Slack pairings..."
    if timeout 20s kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \
        node dist/index.js pairing list slack; then
        return
    fi

    if timeout 20s kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \
        node dist/index.js pairing list; then
        return
    fi

    log_warn "Slack pairing list timed out or failed. You can still approve a code manually."
}

approve_pairing() {
    log_info "Approving Slack pairing code: $PAIRING_CODE"
    if ! timeout 30s kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \
        node dist/index.js pairing approve slack "$PAIRING_CODE"; then
        log_error "Slack pairing approval timed out or failed."
        echo "Run this manually to retry:"
        echo "  kubectl exec -n $NAMESPACE deployment/$RELEASE_NAME -c main -- \\"
        echo "    node dist/index.js pairing approve slack $PAIRING_CODE"
        exit 1
    fi

    log_info "Slack pairing approved successfully."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -c|--code)
            PAIRING_CODE="$2"
            shift 2
            ;;
        --list)
            LIST_PAIRINGS=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
done

if [ "$RELEASE_NAME" = "openclaw" ]; then
    get_release_name
fi

check_prerequisites

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s || true

if [ -z "$PAIRING_CODE" ]; then
    echo ""
    echo -n "Enter Slack pairing code to approve (leave blank to exit): "
    read -r PAIRING_CODE
fi

if [ -z "$PAIRING_CODE" ]; then
    if [ "$LIST_PAIRINGS" = false ]; then
        echo -n "List pending Slack pairings now? [y/N]: "
        read -r list_now
        if [[ "${list_now:-N}" =~ ^[Yy]$ ]]; then
            LIST_PAIRINGS=true
        fi
    fi

    if [ "$LIST_PAIRINGS" = true ]; then
        list_pairings
        echo ""
        echo -n "Enter Slack pairing code to approve (leave blank to exit): "
        read -r PAIRING_CODE
    fi
fi

if [ -z "$PAIRING_CODE" ]; then
    log_warn "Pairing approval skipped."
    exit 0
fi

approve_pairing
