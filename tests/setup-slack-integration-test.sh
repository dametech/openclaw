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
assert_contains 'SLACK_VALUES_FILE="/tmp/${RELEASE_NAME}-slack-values.yaml"'
assert_contains 'CURRENT_CONFIG_JSON="/tmp/${RELEASE_NAME}-openclaw-current.json"'
assert_contains 'MERGED_CONFIG_JSON="/tmp/${RELEASE_NAME}-openclaw-slack-config.json"'
assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains 'read -r input_name'
assert_contains 'RELEASE_NAME="$input_name"'
assert_contains 'ensure_release_exists()'
assert_contains 'kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE"'
assert_contains 'kubectl get secret "$ENV_SECRET_NAME" -n "$NAMESPACE"'
assert_contains 'python3 not found'
assert_contains 'helm upgrade "$RELEASE_NAME" openclaw-community/openclaw \'
assert_contains '--reuse-values \'
assert_contains '--timeout 10m'
assert_contains 'kubectl wait --for=condition=available deployment/"$RELEASE_NAME" \'
assert_contains 'Helm upgrade did not report ready within the timeout. Checking actual deployment readiness...'
assert_contains 'Deployment became available after the Helm timeout. Continuing.'
assert_contains 'show_k8s_diagnostics()'
assert_contains 'kubectl get deploy,rs,pods -n "$NAMESPACE" | grep "$RELEASE_NAME" || true'
assert_contains 'kubectl wait --for=condition=ready pod \'
assert_contains '-l "app.kubernetes.io/instance=$RELEASE_NAME"'
assert_contains 'kubectl logs -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -c main --tail=30 \'
assert_contains 'kubectl exec -n openclaw deployment/$RELEASE_NAME -c main -- \\'
assert_contains 'echo -n "Open Slack now, send a DM to the bot, then launch the pairing helper? [Y/n]: "'
assert_contains './approve-slack-pairing.sh --release "$RELEASE_NAME"'
assert_contains 'kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \'
assert_contains 'cat /home/node/.openclaw/openclaw.json > "$CURRENT_CONFIG_JSON"'
assert_contains 'slack["appToken"] = "\${SLACK_APP_TOKEN}"'
assert_contains 'slack["botToken"] = "\${SLACK_BOT_TOKEN}"'
assert_contains 'slack["groupPolicy"] = "open"'
assert_contains 'cat > "$SLACK_VALUES_FILE" <<EOF'
assert_contains 'name: $ENV_SECRET_NAME'
assert_contains 'name: $SLACK_SECRET_NAME'
assert_contains '$(sed '\''s/^/          /'\'' "$MERGED_CONFIG_JSON")'
assert_contains 'name: ${RELEASE_NAME}-slack-tokens'
