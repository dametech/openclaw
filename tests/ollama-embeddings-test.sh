#!/bin/bash

set -euo pipefail

DEPLOY_SCRIPT="deploy-ollama-embeddings.sh"
OPENCLAW_DEPLOY_SCRIPT="openclaw-deploy.sh"
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
assert_contains "$OPENCLAW_DEPLOY_SCRIPT" '"memorySearch": {'
assert_contains "$OPENCLAW_DEPLOY_SCRIPT" 'http://ollama-embeddings.openclaw.svc.cluster.local:11434'
assert_contains "$DEPLOYMENT_TEMPLATE" 'kind: Deployment'
assert_contains "$DEPLOYMENT_TEMPLATE" 'image: ollama/ollama'
assert_contains "$DEPLOYMENT_TEMPLATE" 'ollama pull ${OLLAMA_EMBEDDINGS_MODEL}'
assert_contains "$SERVICE_TEMPLATE" 'type: ClusterIP'
assert_contains "$SERVICE_TEMPLATE" 'port: 11434'
assert_contains "$NETWORKPOLICY_TEMPLATE" 'kind: NetworkPolicy'
assert_contains "$NETWORKPOLICY_TEMPLATE" 'app.kubernetes.io/name: openclaw'
assert_contains "$NETWORKPOLICY_TEMPLATE" 'port: 11434'

echo "ollama embeddings checks passed"
