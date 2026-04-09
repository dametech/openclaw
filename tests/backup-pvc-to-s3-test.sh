#!/bin/bash

set -euo pipefail

SCRIPT="backup-pvc-to-s3.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'Usage: $0 [OPTIONS]'
assert_contains '--release-name NAME'
assert_contains '--pvc-name NAME'
assert_contains '--cluster NAME'
assert_contains '--timeout DURATION'
assert_contains 'SECRET_NAME="openclaw-backup-aws"'
assert_contains 'SCRIPT_CONFIGMAP_NAME="openclaw-backup-script"'
assert_contains 'basename "$KUBECONFIG_PATH"'
assert_contains 'context_basename="${context_basename%.yaml}"'
assert_contains 'context_basename="${context_basename%.yml}"'
assert_contains 'BACKUP_CLUSTER="$(detect_cluster_id)"'
assert_contains 'kubectl get pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME"'
assert_contains 'Multiple PVCs found for release $RELEASE_NAME'
assert_contains 'Backup script ConfigMap $SCRIPT_CONFIGMAP_NAME not found in namespace $NAMESPACE'
assert_contains 'job_name="openclaw-pvc-backup-${safe_instance}-$(date -u +%s)"'
assert_contains 'image: python:3.11-slim'
assert_contains 'command: ["python3", "/scripts/openclaw-backup-s3.py"]'
assert_contains 'name: BACKUP_CLUSTER'
assert_contains 'name: BACKUP_INSTANCE'
assert_contains 'name: BACKUP_PVC'
assert_contains 'claimName: ${PVC_NAME}'
assert_contains 'kubectl wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout="$WAIT_TIMEOUT"'
assert_contains 'kubectl wait --for=condition=failed job/"$JOB_NAME" -n "$NAMESPACE" --timeout="$WAIT_TIMEOUT"'
assert_contains 'Backup job failed.'
assert_contains 'kubectl logs -n "$NAMESPACE" job/"$JOB_NAME"'
assert_contains 'kubectl describe job -n "$NAMESPACE" "$JOB_NAME"'
assert_contains 'kubectl get pods -n "$NAMESPACE" -l "job-name=$JOB_NAME" -o wide'
assert_contains 'kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 20'

echo "backup-pvc-to-s3.sh checks passed"
