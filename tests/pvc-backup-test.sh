#!/bin/bash

set -euo pipefail

assert_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -Fq -- "$pattern" "$file"; then
        echo "missing expected pattern in $file: $pattern" >&2
        exit 1
    fi
}

assert_contains k8s/pvc-backup-cronjob.yaml 'kind: ServiceAccount'
assert_contains k8s/pvc-backup-cronjob.yaml 'kind: Role'
assert_contains k8s/pvc-backup-cronjob.yaml 'kind: RoleBinding'
assert_contains k8s/pvc-backup-cronjob.yaml 'name: openclaw-pvc-backup-dispatcher'
assert_contains k8s/pvc-backup-cronjob.yaml 'image: bitnami/kubectl:latest'
assert_contains k8s/pvc-backup-cronjob.yaml 'kubectl get pvc -n "$NAMESPACE"'
assert_contains k8s/pvc-backup-cronjob.yaml 'app.kubernetes.io/instance'
assert_contains k8s/pvc-backup-cronjob.yaml 'BACKUP_CLUSTER'
assert_contains k8s/pvc-backup-cronjob.yaml 'BACKUP_INSTANCE'
assert_contains k8s/pvc-backup-cronjob.yaml 'BACKUP_PVC'
assert_contains k8s/pvc-backup-cronjob.yaml 'claimName: ${pvc_name}'
assert_contains k8s/pvc-backup-cronjob.yaml 'ttlSecondsAfterFinished: 300'
assert_contains k8s/pvc-backup-cronjob.yaml 'successfulJobsHistoryLimit: 0'
assert_contains k8s/pvc-backup-cronjob.yaml 'failedJobsHistoryLimit: 0'

assert_contains scripts/openclaw-backup-s3.py 'BACKUP_CLUSTER = os.environ.get("BACKUP_CLUSTER", "au01-0")'
assert_contains scripts/openclaw-backup-s3.py 'BACKUP_INSTANCE = os.environ.get("BACKUP_INSTANCE", "unknown-instance")'
assert_contains scripts/openclaw-backup-s3.py 'BACKUP_PVC = os.environ.get("BACKUP_PVC", "openclaw-data")'
assert_contains scripts/openclaw-backup-s3.py 'BACKUP_PREFIX = f"openclaw-backups/{BACKUP_CLUSTER}/{BACKUP_INSTANCE}/{BACKUP_PVC}"'
