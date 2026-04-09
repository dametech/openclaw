#!/bin/bash

set -euo pipefail

SCRIPT="sync-openclaw-shared-config.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"'
assert_contains 'NAMESPACE="openclaw"'
assert_contains 'SYNC_TIMEOUT="300s"'
assert_contains 'PARALLELISM="3"'
assert_contains 'kubectl get deployment -n "$NAMESPACE" -o jsonpath='
assert_contains "awk -F '\\t' '\$2 ~ /(^|,)main,(|\$)/ { print \$1 }'"
assert_contains 'sync_deployment "$deployment" &'
assert_contains 'if [ "${#active_pids[@]}" -ge "$PARALLELISM" ]; then'
assert_contains 'reap_oldest_job'
assert_contains 'kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/instance=$deployment"'
assert_contains 'kubectl exec -n "$NAMESPACE" "$pod_name" -c main -- mkdir -p "$CONFIG_ROOT/plugins" "$CONFIG_ROOT/skills" "$CONFIG_ROOT/workspace"'
assert_contains 'kubectl cp openclaw/plugins/. "$NAMESPACE/$pod_name:$CONFIG_ROOT/plugins" -c main'
assert_contains 'kubectl cp openclaw/skills/. "$NAMESPACE/$pod_name:$CONFIG_ROOT/skills" -c main'
assert_contains 'kubectl cp openclaw/workspace/. "$NAMESPACE/$pod_name:$CONFIG_ROOT/workspace" -c main'
assert_contains 'kubectl rollout restart "deployment/$deployment" -n "$NAMESPACE"'
assert_contains 'kubectl rollout status "deployment/$deployment" -n "$NAMESPACE" --timeout="$SYNC_TIMEOUT"'
assert_contains "Shared plugins, skills, and workspace synced to all OpenClaw deployments."

echo "sync-openclaw-shared-config.sh checks passed"
