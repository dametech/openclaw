#!/bin/bash
#
# Restore an OpenClaw PVC backup from S3 into a Kubernetes PVC.
#

set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
SECRET_NAME="openclaw-backup-aws"
PVC_NAME=""
PVC_SIZE="5Gi"
PVC_STORAGE_CLASS="talos-hostpath"
S3_URI=""
RELEASE_NAME=""
RESTORE_POD_NAME=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Creates a PVC if needed, restores an OpenClaw backup from S3 into it, and prints
the matching openclaw-deploy.sh command to launch a new instance against that PVC.

Options:
  -n, --namespace NAME        Kubernetes namespace (default: openclaw)
  -k, --kubeconfig PATH       Kubeconfig path (default: ~/.kube/au01-0.yaml)
  -s, --s3-uri URI            Full S3 backup object URI to restore from (.tar.gz)
  -p, --pvc-name NAME         Target PVC name to create/use
  -z, --pvc-size SIZE         Target PVC size (default: 5Gi)
  -c, --storage-class NAME    Storage class (default: talos-hostpath)
  -r, --release-name NAME     Suggested release name to print in follow-up deploy command
  -h, --help                  Show this help

Examples:
  $0
  $0 --s3-uri s3://dame-openclaw-backup/openclaw-backups/au01-0/oc-sm/openclaw-data/2026-04-07T020000Z.tar.gz --pvc-name oc-sm-restore-data
  $0 --s3-uri s3://dame-openclaw-backup/openclaw-backups/au01-0/oc-sm/openclaw-data/2026-04-07T020000Z.tar.gz --pvc-name oc-sm-restore-data --release-name oc-sm-restore
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -s|--s3-uri)
            S3_URI="$2"
            shift 2
            ;;
        -p|--pvc-name)
            PVC_NAME="$2"
            shift 2
            ;;
        -z|--pvc-size)
            PVC_SIZE="$2"
            shift 2
            ;;
        -c|--storage-class)
            PVC_STORAGE_CLASS="$2"
            shift 2
            ;;
        -r|--release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

export_kubeconfig() {
    export KUBECONFIG="$KUBECONFIG_PATH"
}

check_prerequisites() {
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found"
        exit 1
    fi

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_PATH"
        exit 1
    fi
}

prompt_inputs() {
    local input

    if [ -z "$S3_URI" ]; then
        echo -n "Enter full S3 backup URI (.tar.gz object): "
        read -r input
        S3_URI="$input"
    fi

    if [ -z "$PVC_NAME" ]; then
        echo -n "Enter target PVC name: "
        read -r input
        PVC_NAME="$input"
    fi

    echo -n "Enter namespace [$NAMESPACE]: "
    read -r input
    if [ -n "${input:-}" ]; then
        NAMESPACE="$input"
    fi

    echo -n "Enter PVC size [$PVC_SIZE]: "
    read -r input
    if [ -n "${input:-}" ]; then
        PVC_SIZE="$input"
    fi

    echo -n "Enter storage class [$PVC_STORAGE_CLASS]: "
    read -r input
    if [ -n "${input:-}" ]; then
        PVC_STORAGE_CLASS="$input"
    fi

    if [ -z "$RELEASE_NAME" ]; then
        echo -n "Enter OpenClaw release name for deploy [$PVC_NAME]: "
        read -r input
        if [ -n "${input:-}" ]; then
            RELEASE_NAME="$input"
        else
            RELEASE_NAME="$PVC_NAME"
        fi
    fi

    if [ -z "$S3_URI" ] || [ -z "$PVC_NAME" ]; then
        log_error "S3 URI and PVC name are required"
        exit 1
    fi

    if [[ "$S3_URI" != s3://*.tar.gz ]]; then
        log_error "S3 URI must be a full s3://.../.tar.gz object path"
        exit 1
    fi
}

check_cluster_access() {
    export_kubeconfig
    kubectl get ns "$NAMESPACE" >/dev/null
}

check_backup_secret() {
    export_kubeconfig
    if ! kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" >/dev/null 2>&1; then
        log_error "Backup secret $SECRET_NAME not found in namespace $NAMESPACE"
        log_error "Run ./setup-pvc-backup.sh first, or create the secret manually."
        exit 1
    fi
}

create_target_pvc() {
    export_kubeconfig

    if kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" >/dev/null 2>&1; then
        log_error "PVC $PVC_NAME already exists in namespace $NAMESPACE"
        log_error "Choose a new PVC name or delete the existing PVC first."
        exit 1
    fi

    log_info "Creating target PVC $PVC_NAME..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/instance: $RELEASE_NAME
    app.kubernetes.io/managed-by: restore-pvc-backup
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: $PVC_STORAGE_CLASS
EOF

    log_info "PVC $PVC_NAME created. Binding will occur when the restore pod is scheduled."
}

create_restore_pod() {
    export_kubeconfig
    RESTORE_POD_NAME="restore-${PVC_NAME}-$(date +%s)"

    log_info "Creating restore pod $RESTORE_POD_NAME..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $RESTORE_POD_NAME
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: download
      image: amazon/aws-cli:2.17.40
      command: ["/bin/sh", "-c", "sleep 3600"]
      envFrom:
        - secretRef:
            name: $SECRET_NAME
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
      volumeMounts:
        - name: work
          mountPath: /work
    - name: extract
      image: python:3.12-alpine
      command: ["/bin/sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
      volumeMounts:
        - name: work
          mountPath: /work
        - name: data
          mountPath: /restore-target
  volumes:
    - name: work
      emptyDir: {}
    - name: data
      persistentVolumeClaim:
        claimName: $PVC_NAME
EOF

    kubectl wait --for=condition=Ready pod/"$RESTORE_POD_NAME" -n "$NAMESPACE" --timeout=180s
}

restore_backup() {
    export_kubeconfig

    log_info "Restoring backup from $S3_URI into PVC $PVC_NAME..."
    kubectl exec -n "$NAMESPACE" -c download "$RESTORE_POD_NAME" -- sh -lc "
set -e
aws s3 cp '$S3_URI' /work/backup.tar.gz
"

    kubectl exec -n "$NAMESPACE" -c extract "$RESTORE_POD_NAME" -- sh -lc "
set -e
rm -rf /work/restore
mkdir -p /work/restore
python3 - <<'PY'
import tarfile
with tarfile.open('/work/backup.tar.gz', 'r:gz') as tar:
    tar.extractall('/work/restore', filter='data')
PY
cp -r /work/restore/openclaw/. /restore-target/
"
}

verify_restore() {
    export_kubeconfig

    log_info "Verifying restored contents..."
    kubectl exec -n "$NAMESPACE" -c extract "$RESTORE_POD_NAME" -- sh -lc "
set -e
test -d /restore-target
test -f /restore-target/openclaw.json || test -d /restore-target/workspace
ls -la /restore-target | sed -n '1,20p'
"
}

cleanup_restore_pod() {
    export_kubeconfig

    if [ -n "${RESTORE_POD_NAME:-}" ]; then
        kubectl delete pod -n "$NAMESPACE" "$RESTORE_POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
    fi
}

show_next_steps() {
    echo ""
    log_info "Restore completed successfully."
    echo ""
    echo "Target PVC: $PVC_NAME"
    echo "Backup source: $S3_URI"
    echo "Suggested release name: $RELEASE_NAME"
    echo ""
    echo "To deploy a new OpenClaw instance using this restored PVC:"
    echo "./openclaw-deploy.sh --release-name $RELEASE_NAME --existing-pvc $PVC_NAME"
}

trap cleanup_restore_pod EXIT

check_prerequisites
prompt_inputs
check_cluster_access
check_backup_secret
create_target_pvc
create_restore_pod
restore_backup
verify_restore
show_next_steps
