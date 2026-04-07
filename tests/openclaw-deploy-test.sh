#!/bin/bash

set -euo pipefail

SCRIPT="openclaw-deploy.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains 'SECRET_NAME="${RELEASE_NAME}-env-secret"'
assert_contains 'VALUES_FILE="/tmp/${RELEASE_NAME}-values.yaml"'
assert_contains 'fullnameOverride: $RELEASE_NAME'
assert_contains 'echo -n "Enter your AWS Access Key ID: "'
assert_contains 'echo -n "Enter your AWS Secret Access Key: "'
assert_contains 'AWS_ACCESS_KEY_ID'
assert_contains 'AWS_SECRET_ACCESS_KEY'
assert_contains 'AWS_SESSION_TOKEN'
assert_contains 'Using AWS_ACCESS_KEY_ID from environment'
assert_contains 'AWS_ACCESS_KEY_ID is required'
assert_contains 'AWS_SECRET_ACCESS_KEY is required'
assert_contains '"model": {'
assert_contains '"primary": "amazon-bedrock/global.anthropic.claude-sonnet-4-6"'
assert_contains '"models": {'
assert_contains '"amazon-bedrock/global.anthropic.claude-sonnet-4-6": {'
assert_contains '"amazon-bedrock/global.anthropic.claude-opus-4-6-v1": {'
assert_contains '"amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0": {'
assert_contains '"cacheRetention": "ephemeral"'
assert_contains '"cacheRetention": "none"'
assert_contains '"userTimezone": "Australia/Brisbane"'
assert_contains '"id": "main"'
assert_contains '"default": true'
assert_contains 'name: $SECRET_NAME'
assert_contains 'name: $SECRET_NAME'
assert_contains 'helm upgrade "$RELEASE_NAME" "$HELM_REPO/openclaw" \'
assert_contains '--values "$VALUES_FILE" \'
assert_contains '"pod-delegate": {'
assert_contains '/home/node/.openclaw/plugins/pod-delegate'
assert_contains 'pod-delegate-plugin:'
assert_contains 'name: '\''{{ .Release.Name }}-pod-delegate-plugin'\'''
assert_contains 'mkdir -p /home/node/.openclaw/plugins/pod-delegate'
assert_contains 'cp /plugin-source-pod-delegate/openclaw.plugin.json /home/node/.openclaw/plugins/pod-delegate/openclaw.plugin.json'
assert_contains 'cp /plugin-source-pod-delegate/index.js /home/node/.openclaw/plugins/pod-delegate/index.js'
assert_contains 'POD_DELEGATE_BOOTSTRAP_MARKER="## Inter-Pod Delegation"'
assert_contains '"responses": {'
assert_contains 'POST /v1/responses'
assert_contains 'gateway.http.endpoints.responses.enabled'
assert_contains '"memorySearch": {'
assert_contains '"provider": "ollama"'
assert_contains 'http://ollama-embeddings.openclaw.svc.cluster.local:11434'
assert_contains 'This pod may start with no configured delegate targets.'
assert_contains 'delegate pod/service name and delegate pod gateway token'
assert_contains 'The plugin derives the in-cluster service URL from the target name.'
assert_contains 'exec openclaw gateway --bind lan --port 18789'
assert_contains 'openclaw.json: |'
assert_contains '"controlUi": {'
assert_contains '"allowedOrigins": ['
assert_contains '"http://127.0.0.1:18789"'
assert_contains '"http://localhost:18789"'
assert_contains '18789'
assert_contains 'deployment/$RELEASE_NAME'
assert_contains 'svc/$RELEASE_NAME'
assert_contains 'show_deploy_diagnostics()'
assert_contains 'check_cluster_disk_pressure()'
assert_contains 'Checking cluster for disk pressure...'
assert_contains 'kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints --no-headers'
assert_contains 'node.kubernetes.io/disk-pressure'
assert_contains 'Cluster has node(s) under disk pressure:'
assert_contains 'helm status "$RELEASE_NAME" -n "$NAMESPACE" || true'
assert_contains 'kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o wide || true'
assert_contains 'kubectl describe deployment "$RELEASE_NAME" -n "$NAMESPACE" || true'
assert_contains 'kubectl describe pod -n "$NAMESPACE" "$pod_name" || true'
assert_contains 'Helm deployment did not become ready. Gathering diagnostics...'
assert_contains 'if ! helm'
assert_contains 'AWS_ACCESS_KEY_ID:'
assert_contains 'AWS_SECRET_ACCESS_KEY:'
assert_contains 'AWS_REGION: "ap-southeast-2"'
assert_contains 'kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found'
assert_contains '"gateway": {'
assert_contains '"mode": "local"'
assert_contains '"allowedOrigins": ['
assert_contains '"providers": {'
assert_contains '"amazon-bedrock": {'
assert_contains '"baseUrl": "https://bedrock-runtime.ap-southeast-2.amazonaws.com"'
assert_contains '"apiKey": "aws-sdk"'
assert_contains '"api": "bedrock-converse-stream"'
assert_contains '"bedrockDiscovery": {'
assert_contains '"enabled": false'
assert_contains '"region": "ap-southeast-2"'
assert_contains '"providerFilter": ['
assert_contains '"anthropic"'
assert_contains '"amazon"'

if grep -Fq -- '- loopback' "$SCRIPT"; then
    echo "unexpected loopback bind mode in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'POST_RENDERER_FILE=' "$SCRIPT" || grep -Fq -- '--post-renderer' "$SCRIPT"; then
    echo "unexpected post-renderer logic in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'yaml.safe_load_all' "$SCRIPT"; then
    echo "unexpected embedded yaml post-renderer in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'ANTHROPIC_API_KEY' "$SCRIPT"; then
    echo "unexpected Anthropic API key handling in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'anthropic/claude-opus-4-6' "$SCRIPT"; then
    echo "unexpected Anthropic model handling in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- '"id": "opus"' "$SCRIPT" || grep -Fq -- '"id": "haiku"' "$SCRIPT"; then
    echo "unexpected separate model agents in $SCRIPT" >&2
    exit 1
fi

echo "openclaw-deploy.sh checks passed"
