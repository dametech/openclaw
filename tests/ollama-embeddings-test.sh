#!/bin/bash

set -euo pipefail

DEPLOY_SCRIPT="deploy-ollama-embeddings.sh"
OPENCLAW_CONFIG_TEMPLATE="openclaw/openclaw.json"
DEPLOYMENT_TEMPLATE="k8s/ollama-embeddings-deployment.yaml"
SERVICE_TEMPLATE="k8s/ollama-embeddings-service.yaml"
NETWORKPOLICY_TEMPLATE="k8s/ollama-embeddings-networkpolicy.yaml"

assert_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -Fq -- "$pattern" "$file"; then
        echo "missing expected pattern in $file: $pattern" >&2
        exit 1
    fi
}

assert_contains "$DEPLOY_SCRIPT" 'OLLAMA_EMBEDDINGS_MODEL'
assert_contains "$DEPLOY_SCRIPT" 'http://ollama-embeddings.${NAMESPACE}.svc.cluster.local:11434'
assert_contains "$DEPLOY_SCRIPT" 'Applying Ollama embeddings resources...'
assert_contains "$DEPLOY_SCRIPT" 'k8s/ollama-embeddings-deployment.yaml'
assert_contains "$DEPLOY_SCRIPT" 'k8s/ollama-embeddings-service.yaml'
assert_contains "$DEPLOY_SCRIPT" 'k8s/ollama-embeddings-networkpolicy.yaml'
assert_contains "$OPENCLAW_CONFIG_TEMPLATE" '"memorySearch": {'
assert_contains "$OPENCLAW_CONFIG_TEMPLATE" 'http://ollama-embeddings.openclaw.svc.cluster.local:11434'
assert_contains "$DEPLOYMENT_TEMPLATE" 'kind: Deployment'
assert_contains "$DEPLOYMENT_TEMPLATE" 'image: ollama/ollama:0.13.5'
assert_contains "$DEPLOYMENT_TEMPLATE" 'name: OLLAMA_NUM_PARALLEL'
assert_contains "$DEPLOYMENT_TEMPLATE" 'value: "2"'
assert_contains "$DEPLOYMENT_TEMPLATE" 'name: OLLAMA_MAX_QUEUE'
assert_contains "$DEPLOYMENT_TEMPLATE" 'value: "32"'
assert_contains "$DEPLOYMENT_TEMPLATE" 'name: OLLAMA_KEEP_ALIVE'
assert_contains "$DEPLOYMENT_TEMPLATE" 'value: "30m"'
assert_contains "$DEPLOYMENT_TEMPLATE" 'ollama pull ${OLLAMA_EMBEDDINGS_MODEL}'
assert_contains "$DEPLOYMENT_TEMPLATE" 'cpu: 2'
assert_contains "$DEPLOYMENT_TEMPLATE" 'memory: 2Gi'
assert_contains "$DEPLOYMENT_TEMPLATE" 'cpu: 3'
assert_contains "$DEPLOYMENT_TEMPLATE" 'memory: 6Gi'
assert_contains "$SERVICE_TEMPLATE" 'type: ClusterIP'
assert_contains "$SERVICE_TEMPLATE" 'port: 11434'
assert_contains "$NETWORKPOLICY_TEMPLATE" 'kind: NetworkPolicy'
assert_contains "$NETWORKPOLICY_TEMPLATE" 'app.kubernetes.io/name: openclaw'
assert_contains "$NETWORKPOLICY_TEMPLATE" 'port: 11434'

echo "ollama embeddings checks passed"
