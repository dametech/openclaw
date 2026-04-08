#!/bin/bash

set -euo pipefail

SCRIPT="setup-pvc-backup.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"'
assert_contains 'NAMESPACE="openclaw"'
assert_contains 'BACKUP_CLUSTER=""'
assert_contains 'S3_BUCKET="dame-openclaw-backup"'
assert_contains 'SECRET_NAME="openclaw-backup-aws"'
assert_contains 'SCRIPT_CONFIGMAP_NAME="openclaw-backup-script"'
assert_contains 'MANIFEST_PATH="k8s/pvc-backup-cronjob.yaml"'
assert_contains 'kubectl config current-context'
assert_contains 'BACKUP_CLUSTER="$(detect_cluster_id)"'
assert_contains 'kubectl get secret -n "$NAMESPACE" "$SECRET_NAME"'
assert_contains 'kubectl create secret generic "$SECRET_NAME"'
assert_contains '--from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"'
assert_contains '--from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"'
assert_contains '--from-literal=AWS_REGION="$AWS_REGION"'
assert_contains '--from-literal=S3_BUCKET="$S3_BUCKET"'
assert_contains 'kubectl create configmap "$SCRIPT_CONFIGMAP_NAME"'
assert_contains '--from-file=openclaw-backup-s3.py="$SCRIPT_SOURCE"'
assert_contains 'kubectl apply -f "$MANIFEST_PATH"'
assert_contains 'kubectl create job --from=cronjob/openclaw-pvc-backup-dispatcher'
