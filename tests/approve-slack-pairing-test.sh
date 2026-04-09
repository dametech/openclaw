#!/bin/bash

set -euo pipefail

SCRIPT="approve-slack-pairing.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

if [ ! -f "$SCRIPT" ]; then
    echo "missing expected file: $SCRIPT" >&2
    exit 1
fi

assert_contains 'KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"'
assert_contains 'NAMESPACE="openclaw"'
assert_contains 'RELEASE_NAME="openclaw"'
assert_contains 'PAIRING_CODE=""'
assert_contains 'LIST_PAIRINGS=false'
assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains 'echo -n "Enter Slack pairing code to approve (leave blank to exit): "'
assert_contains 'echo -n "List pending Slack pairings now? [y/N]: "'
assert_contains 'kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s || true'
assert_contains 'timeout 20s kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \'
assert_contains 'node dist/index.js pairing list slack'
assert_contains 'Slack pairing list timed out or failed. You can still approve a code manually.'
assert_contains 'timeout 30s kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \'
assert_contains 'Slack pairing approval timed out or failed.'
assert_contains 'node dist/index.js pairing approve slack "$PAIRING_CODE"'
assert_contains 'kubectl exec -n $NAMESPACE deployment/$RELEASE_NAME -c main -- \\'
assert_contains 'Pairing approval skipped.'
assert_contains 'Slack pairing approved successfully.'
assert_contains '--code CODE'
assert_contains '--list'
assert_contains '--release NAME'
assert_contains '--namespace NAME'
assert_contains '--kubeconfig PATH'

echo "approve-slack-pairing.sh checks passed"
