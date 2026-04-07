#!/bin/bash

set -euo pipefail

SCRIPT="setup-slack-integration.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'RELEASE_NAME="openclaw"'
assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains 'read -r input_name'
assert_contains 'RELEASE_NAME="$input_name"'
assert_contains 'helm upgrade "$RELEASE_NAME" openclaw-community/openclaw \'
assert_contains 'kubectl wait --for=condition=ready pod \'
assert_contains '-l "app.kubernetes.io/instance=$RELEASE_NAME"'
assert_contains 'kubectl logs -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -c main --tail=30 \'
assert_contains 'kubectl exec -n openclaw deployment/$RELEASE_NAME -c main -- \\'
assert_contains 'name: ${RELEASE_NAME}-slack-tokens'
