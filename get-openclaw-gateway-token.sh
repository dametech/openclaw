#!/bin/bash
#
# OpenClaw Gateway Token Helper
# Prints the current gateway token for a named OpenClaw deployment
#

set -e

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
RELEASE_NAME="openclaw"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Prints the current OpenClaw gateway token for a deployment."
    echo ""
    echo "Options:"
    echo "  -r, --release NAME      Release name"
    echo "  -n, --namespace NAME    Namespace (default: openclaw)"
    echo "  -k, --kubeconfig PATH   Kubeconfig path (default: \$HOME/.kube/au01-0.yaml)"
    echo "  -h, --help              Show this help message"
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

if [ "$RELEASE_NAME" = "openclaw" ]; then
    get_release_name
fi

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s || true

sleep 5

GATEWAY_TOKEN=$(kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -o '"token": "[^"]*"' | cut -d'"' -f4)

printf "%s\n" "$GATEWAY_TOKEN"
