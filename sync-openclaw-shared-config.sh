#!/bin/bash
#
# Sync shared plugins, skills, and workspace into all OpenClaw pods, then restart them.
#

set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
SYNC_TIMEOUT="300s"
PARALLELISM="3"
CONFIG_ROOT="/home/node/.openclaw"

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Syncs repo openclaw/plugins/, openclaw/skills/, and openclaw/workspace/ into all OpenClaw deployments in the namespace,"
    echo "restarts each deployment, and prints rollout status."
    echo ""
    echo "Options:"
    echo "  -n, --namespace NAME    Namespace (default: openclaw)"
    echo "  -k, --kubeconfig PATH   Kubeconfig path (default: \$HOME/.kube/au01-0.yaml)"
    echo "  -t, --timeout DURATION  Rollout timeout (default: 300s)"
    echo "  -p, --parallelism NUM   Concurrent deployment syncs (default: 3)"
    echo "  -h, --help              Show this help message"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -t|--timeout)
            SYNC_TIMEOUT="$2"
            shift 2
            ;;
        -p|--parallelism)
            PARALLELISM="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1" >&2
            echo ""
            show_usage
            exit 1
            ;;
    esac
done

if [ ! -d "openclaw/plugins" ]; then
    log_error "openclaw/plugins directory not found in current working directory."
    exit 1
fi

if [ ! -d "openclaw/skills" ]; then
    log_error "openclaw/skills directory not found in current working directory."
    exit 1
fi

if [ ! -d "openclaw/workspace" ]; then
    log_error "openclaw/workspace directory not found in current working directory."
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

if [ ! -f "$KUBECONFIG_PATH" ]; then
    log_error "Kubeconfig not found at $KUBECONFIG_PATH"
    exit 1
fi

if ! [[ "$PARALLELISM" =~ ^[0-9]+$ ]] || [ "$PARALLELISM" -lt 1 ]; then
    log_error "Invalid parallelism '$PARALLELISM'. Must be a positive integer."
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

mapfile -t deployments < <(
    kubectl get deployment -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.template.spec.containers[*]}{.name}{","}{end}{"\n"}{end}' |
        awk -F '\t' '$2 ~ /(^|,)main,(|$)/ { print $1 }'
)

if [ "${#deployments[@]}" -eq 0 ]; then
    log_warn "No OpenClaw deployments found in namespace '$NAMESPACE'."
    exit 0
fi

overall_status=0
declare -a active_pids=()
declare -a active_deployments=()
tmp_dir=$(mktemp -d)

cleanup() {
    rm -rf "$tmp_dir"
}

trap cleanup EXIT

sync_deployment() {
    local deployment="$1"
    local pod_name

    log_info "Syncing shared config to deployment '$deployment'..."

    pod_name=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/instance=$deployment" -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        log_warn "No pod found for deployment '$deployment'. Skipping."
        return 1
    fi

    kubectl exec -n "$NAMESPACE" "$pod_name" -c main -- mkdir -p "$CONFIG_ROOT/plugins" "$CONFIG_ROOT/workspace/skills" "$CONFIG_ROOT/workspace"
    kubectl cp openclaw/plugins/. "$NAMESPACE/$pod_name:$CONFIG_ROOT/plugins" -c main
    kubectl cp openclaw/skills/. "$NAMESPACE/$pod_name:$CONFIG_ROOT/workspace/skills" -c main
    kubectl cp openclaw/workspace/. "$NAMESPACE/$pod_name:$CONFIG_ROOT/workspace" -c main

    kubectl rollout restart "deployment/$deployment" -n "$NAMESPACE"

    if kubectl rollout status "deployment/$deployment" -n "$NAMESPACE" --timeout="$SYNC_TIMEOUT"; then
        log_info "Deployment '$deployment' synced and restarted successfully."
        return 0
    fi

    log_error "Deployment '$deployment' failed to become ready after restart."
    return 1
}

reap_oldest_job() {
    local pid="${active_pids[0]}"
    local deployment="${active_deployments[0]}"

    if wait "$pid"; then
        :
    else
        overall_status=1
    fi

    active_pids=("${active_pids[@]:1}")
    active_deployments=("${active_deployments[@]:1}")
}

for deployment in "${deployments[@]}"; do
    sync_deployment "$deployment" &
    active_pids+=("$!")
    active_deployments+=("$deployment")

    if [ "${#active_pids[@]}" -ge "$PARALLELISM" ]; then
        reap_oldest_job
    fi
done

while [ "${#active_pids[@]}" -gt 0 ]; do
    reap_oldest_job
done

if [ "$overall_status" -ne 0 ]; then
    exit "$overall_status"
fi

log_info "Shared plugins, skills, and workspace synced to all OpenClaw deployments."
