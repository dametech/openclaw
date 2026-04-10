#!/bin/bash

set -euo pipefail

SCRIPT="setup-msteams-integration.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'RELEASE_NAME'
assert_contains 'TEAMS_HOSTNAME="${RELEASE_NAME}.openclaw.dametech.net"'
assert_contains 'Enter Microsoft Entra tenant ID'
assert_contains 'Enter Azure app registration (client) ID'
assert_contains 'Enter Azure app registration client secret value'
assert_contains 'if [ -n "${MSTEAMS_APP_ID:-}" ]; then'
assert_contains 'Using MSTEAMS_APP_ID from environment'
assert_contains 'if [ -n "${MSTEAMS_APP_PASSWORD:-}" ]; then'
assert_contains 'Using MSTEAMS_APP_PASSWORD from environment'
assert_contains 'if [ -n "${MSTEAMS_TENANT_ID:-}" ]; then'
assert_contains 'Using MSTEAMS_TENANT_ID from environment'
assert_contains 'SECRET_NAME="${RELEASE_NAME}-teams-credentials"'
assert_contains 'SERVICE_NAME="${RELEASE_NAME}-teams-webhook"'
assert_contains 'INGRESS_NAME="${RELEASE_NAME}-teams-ingress"'
assert_contains 'DEPLOYMENT_LABEL_NAME=$(kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE"'
assert_contains "jsonpath='{.spec.template.metadata.labels.app\\.kubernetes\\.io/name}')"
assert_contains 'app.kubernetes.io/name: ${DEPLOYMENT_LABEL_NAME}'
assert_contains 'kubectl apply -f -'
assert_contains 'kind: Ingress'
assert_contains 'ingressClassName: nginx'
assert_contains 'host: ${TEAMS_HOSTNAME}'
assert_contains 'name: ${RELEASE_NAME}-teams-webhook'
assert_contains 'Installing Teams plugin'
assert_contains 'LOCAL_PLUGIN_DIR="openclaw/plugins/msteams"'
assert_contains 'kubectl cp "$LOCAL_PLUGIN_DIR/." "$NAMESPACE/$POD_NAME:/tmp/openclaw-msteams-source" -c main'
assert_contains 'NPM_CONFIG_CACHE=/home/node/.openclaw/.npm'
assert_contains 'XDG_CACHE_HOME=/home/node/.openclaw/.cache'
assert_contains 'openclaw plugins install /tmp/openclaw-msteams-source'
assert_contains 'Local msteams plugin install failed'
assert_contains 'for cmd in kubectl jq; do'
assert_contains 'cat /home/node/.openclaw/openclaw.json'
assert_contains '.channels.msteams.appId = $appId'
assert_contains '.channels.msteams.appPassword = $appPassword'
assert_contains '.channels.msteams.tenantId = $tenantId'
assert_contains '.channels.msteams.enabled = true'
assert_contains '.channels.msteams.webhook.port = $port'
assert_contains '.channels.msteams.webhook.path = $path'
assert_contains '.channels.msteams.dmPolicy = "open"'
assert_contains '.channels.msteams.allowFrom = ["*"]'
assert_contains '.channels.msteams.groupPolicy = "open"'
assert_contains "sh -c 'cat > /home/node/.openclaw/openclaw.json'"
assert_contains 'pgrep -xo openclaw'
assert_contains 'kill -USR1 "$gateway_pid"'
assert_contains 'https://${TEAMS_HOSTNAME}/api/messages'

if grep -Fq -- 'kubectl rollout restart deployment/"$RELEASE_NAME"' "$SCRIPT"; then
    echo "unexpected deployment rollout restart in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'openclaw config set "$@"' "$SCRIPT"; then
    echo "unexpected openclaw config cli usage in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'openclaw_config_set' "$SCRIPT"; then
    echo "unexpected openclaw config helper in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'kill -HUP 1' "$SCRIPT"; then
    echo "unexpected HUP reload in $SCRIPT" >&2
    exit 1
fi
