#!/bin/bash

set -euo pipefail

TEMPLATE="openclaw/openclaw.json"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$TEMPLATE"; then
        echo "missing expected pattern in $TEMPLATE: $pattern" >&2
        exit 1
    fi
}

if [ ! -f "$TEMPLATE" ]; then
    echo "missing expected file: $TEMPLATE" >&2
    exit 1
fi

assert_contains '"gateway"'
assert_contains '"auth"'
assert_contains '"token": __GATEWAY_AUTH_TOKEN_JSON__'
assert_contains '"mode": "local"'
assert_contains '"controlUi"'
assert_contains '"allowedOrigins"'
assert_contains '"http://127.0.0.1:18789"'
assert_contains '"http://localhost:18789"'
assert_contains '"responses"'
assert_contains '"agents"'
assert_contains '"primary": "amazon-bedrock/global.anthropic.claude-sonnet-4-6"'
assert_contains '"amazon-bedrock/global.anthropic.claude-sonnet-4-6"'
assert_contains '"amazon-bedrock/global.anthropic.claude-opus-4-6-v1"'
assert_contains '"amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0"'
assert_contains '"cacheRetention": "ephemeral"'
assert_contains '"cacheRetention": "none"'
assert_contains '"userTimezone": "Australia/Brisbane"'
assert_contains '"thinkingDefault": "adaptive"'
assert_contains '"typingMode": "instant"'
assert_contains '"typingIntervalSeconds": 6'
assert_contains '"id": "main"'
assert_contains '"default": true'
assert_contains '"subagents"'
assert_contains '"maxConcurrent": 4'
assert_contains '"memorySearch"'
assert_contains '"provider": "ollama"'
assert_contains 'http://ollama-embeddings.openclaw.svc.cluster.local:11434'
assert_contains '"models"'
assert_contains '"amazon-bedrock"'
assert_contains '"baseUrl": "https://bedrock-runtime.ap-southeast-2.amazonaws.com"'
assert_contains '"apiKey": "aws-sdk"'
assert_contains '"api": "bedrock-converse-stream"'
assert_contains '"plugins"'
assert_contains '"pod-delegate"'
assert_contains '"channels"'
assert_contains '"slack": __SLACK_CHANNEL_JSON__'
assert_contains '"msteams": __MSTEAMS_CHANNEL_JSON__'
assert_contains '__MSGRAPH_TENANT_ID_JSON__'
assert_contains '__MSGRAPH_CLIENT_ID_JSON__'
assert_contains '__JIRA_BASE_URL_JSON__'
assert_contains '__GATEWAY_AUTH_TOKEN_JSON__'
assert_contains '__OLLAMA_EMBEDDINGS_MODEL_JSON__'
assert_contains '__POD_DELEGATE_TARGETS_JSON__'
assert_contains '__SLACK_CHANNEL_JSON__'
assert_contains '__MSTEAMS_CHANNEL_JSON__'
assert_contains '"/home/node/.openclaw/plugins/ms-graph-query"'
assert_contains '"/home/node/.openclaw/plugins/jira-query"'
assert_contains '"/home/node/.openclaw/plugins/pod-delegate"'
assert_contains '"maxConcurrent": 2'

if grep -Fq -- '"tools"' "$TEMPLATE"; then
    echo "unexpected tools block in $TEMPLATE" >&2
    exit 1
fi

echo "openclaw config template checks passed"
