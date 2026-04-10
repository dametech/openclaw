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
assert_contains 'ENV_SECRET_NAME="${RELEASE_NAME}-env-secret"'
assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains 'read -r input_name'
assert_contains 'RELEASE_NAME="$input_name"'
assert_contains 'ensure_release_exists()'
assert_contains 'kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE"'
assert_contains 'show_k8s_diagnostics()'
assert_contains 'kubectl get deploy,rs,pods -n "$NAMESPACE" | grep "$RELEASE_NAME" || true'
assert_contains 'kubectl logs -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -c main --tail=30 \'
assert_contains 'kubectl exec -n openclaw deployment/$RELEASE_NAME -c main -- \\'
assert_contains 'echo -n "Open Slack now, send a DM to the bot, then launch the pairing helper? [Y/n]: "'
assert_contains './approve-slack-pairing.sh --release "$RELEASE_NAME"'
assert_contains 'command -v jq'
assert_contains 'cat /home/node/.openclaw/openclaw.json'
assert_contains '.channels.slack.enabled = true'
assert_contains '.channels.slack.mode = "socket"'
assert_contains '.channels.slack.appToken = $appToken'
assert_contains '.channels.slack.botToken = $botToken'
assert_contains '.channels.slack.groupPolicy = "open"'
assert_contains "sh -c 'cat > /home/node/.openclaw/openclaw.json'"
assert_contains 'pgrep -xo openclaw'
assert_contains 'kill -USR1 "$gateway_pid"'
assert_contains 'name: ${RELEASE_NAME}-slack-tokens'

if grep -Fq -- 'helm upgrade "$RELEASE_NAME" openclaw-community/openclaw' "$SCRIPT"; then
    echo "unexpected helm upgrade flow in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'openclaw config set "$@"' "$SCRIPT"; then
    echo "unexpected openclaw config cli usage in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'kubectl wait --for=condition=ready pod' "$SCRIPT"; then
    echo "unexpected pod readiness wait in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'openclaw_config_set' "$SCRIPT"; then
    echo "unexpected openclaw config helper in $SCRIPT" >&2
    exit 1
fi
