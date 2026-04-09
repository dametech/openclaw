#!/bin/bash

set -euo pipefail

SCRIPT="restore-pvc-backup.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains '--s3-uri URI            Full S3 backup object URI to restore from (.tar.gz)'
assert_contains '--pvc-name NAME'
assert_contains '--pvc-size SIZE'
assert_contains '--storage-class NAME'
assert_contains '--release-name NAME'
assert_contains 'SECRET_NAME="openclaw-backup-aws"'
assert_contains 'PVC_STORAGE_CLASS="talos-hostpath"'
assert_contains 'kind: PersistentVolumeClaim'
assert_contains 'metadata:'
assert_contains 'labels:'
assert_contains 'app.kubernetes.io/instance: $RELEASE_NAME'
assert_contains 'app.kubernetes.io/managed-by: restore-pvc-backup'
assert_contains 'image: amazon/aws-cli:2.17.40'
assert_contains 'image: python:3.12-alpine'
assert_contains 'aws s3 cp'
assert_contains 'python3 - <<'\''PY'\'''
assert_contains "with tarfile.open('/work/backup.tar.gz', 'r:gz') as tar:"
assert_contains "tar.extractall('/work/restore', filter='data')"
assert_contains 'cp -r /work/restore/openclaw/. /restore-target/'
assert_contains 'kubectl wait --for=condition=Ready pod/"$RESTORE_POD_NAME" -n "$NAMESPACE" --timeout=180s'
assert_contains 'Binding will occur when the restore pod is scheduled.'
assert_contains 'allowPrivilegeEscalation: false'
assert_contains 'drop:'
assert_contains 'runAsNonRoot: true'
assert_contains 'seccompProfile:'
assert_contains 'kubectl exec -n "$NAMESPACE" -c extract "$RESTORE_POD_NAME" -- sh -lc "'
assert_contains 'Enter OpenClaw release name for deploy [$PVC_NAME]: '
assert_contains 'RELEASE_NAME="$PVC_NAME"'
assert_contains 'Suggested release name: $RELEASE_NAME'
assert_contains './openclaw-deploy.sh --release-name $RELEASE_NAME --existing-pvc $PVC_NAME'
assert_contains 'Backup secret $SECRET_NAME not found in namespace $NAMESPACE'
assert_contains 'Enter full S3 backup URI (.tar.gz object): '
assert_contains 'S3 URI must be a full s3://.../.tar.gz object path'

echo "restore-pvc-backup.sh checks passed"
