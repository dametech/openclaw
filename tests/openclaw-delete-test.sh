#!/bin/bash

set -euo pipefail

SCRIPT="openclaw-delete.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_not_contains() {
    local pattern="$1"

    if grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "unexpected pattern present: $pattern" >&2
        exit 1
    fi
}

assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains "This will delete the OpenClaw deployment '\$RELEASE_NAME' and associated resources."
assert_contains "Deleting PersistentVolumeClaim(s) for release '\$RELEASE_NAME'..."
assert_contains 'collect_release_pvcs()'
assert_contains 'kubectl get pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o name'
assert_contains 'kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='
assert_contains ".spec.template.spec.volumes[*]"
assert_contains "persistentVolumeClaim.claimName"
assert_contains "sort -u"
assert_contains 'kubectl delete -n "$NAMESPACE" $pvc_names'
assert_contains 'delete_configmaps'
assert_contains 'Deleting ConfigMap(s) for release '\''$RELEASE_NAME'\''...'
assert_contains 'kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-config" --ignore-not-found'
assert_contains 'kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-scripts" --ignore-not-found'
assert_contains 'kubectl wait --for=delete "$pvc_name" -n "$NAMESPACE" --timeout=180s || true'
assert_contains 'delete_pvc'
assert_not_contains 'Delete PersistentVolumeClaim (this will delete all data)?'
assert_not_contains 'Delete namespace'
assert_not_contains 'delete_namespace'
assert_not_contains 'kubectl delete namespace "$NAMESPACE"'

echo "openclaw-delete.sh checks passed"
