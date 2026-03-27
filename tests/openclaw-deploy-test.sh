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
assert_contains 'name: $SECRET_NAME'
assert_contains 'name: $SECRET_NAME'
assert_contains 'helm upgrade "$RELEASE_NAME" "$HELM_REPO/openclaw" \'
assert_contains '--values "$VALUES_FILE" \'
assert_contains '- --bind'
assert_contains '- lan'
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

echo "openclaw-deploy.sh checks passed"
