#!/bin/bash

set -euo pipefail

SCRIPT="get-openclaw-gateway-token.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"'
assert_contains 'NAMESPACE="openclaw"'
assert_contains 'RELEASE_NAME="openclaw"'
assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains 'RELEASE_NAME="$input_name"'
assert_contains 'kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s || true'
assert_contains 'kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json'
assert_contains 'python3 -c '
assert_contains 'print(json.loads(data).get("gateway", {}).get("auth", {}).get("token", "") if data else "")'
assert_contains 'printf "%s\n" "$GATEWAY_TOKEN"'

if grep -Fq -- 'Gateway Token:' "$SCRIPT"; then
    echo "unexpected human-readable label output in $SCRIPT" >&2
    exit 1
fi

echo "get-openclaw-gateway-token.sh checks passed"
