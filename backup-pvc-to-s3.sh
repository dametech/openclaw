#!/bin/bash
#
# Trigger a one-off OpenClaw PVC backup to S3 for a single release/PVC.
#

set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
SECRET_NAME="openclaw-backup-aws"
SCRIPT_CONFIGMAP_NAME="openclaw-backup-script"
RELEASE_NAME=""
PVC_NAME=""
BACKUP_CLUSTER=""
WAIT_TIMEOUT="30m"
WAIT_FOR_COMPLETION=true
JOB_NAME=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "\n${BLUE}==>${NC} ${CYAN}$1${NC}\n"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Triggers a one-off S3 backup job for a single OpenClaw PVC, reusing the same
secret, ConfigMap, and worker-job shape as the cluster backup CronJob.

Options:
  -n, --namespace NAME         Kubernetes namespace (default: openclaw)
  -k, --kubeconfig PATH        Kubeconfig path (default: ~/.kube/au01-0.yaml)
  -r, --release-name NAME      OpenClaw release/instance name (for example: oc-marc)
  -p, --pvc-name NAME          PVC name to back up; auto-resolved from release label if omitted
  -c, --cluster NAME           Backup cluster id for S3 path (defaults to current kube context)
  -t, --timeout DURATION       Wait timeout for the backup Job (default: 30m)
      --no-wait                Create the backup Job and exit without waiting
  -h, --help                   Show this help

Examples:
  $0 --release-name oc-marc
  $0 --release-name oc-marc --pvc-name oc-marc
  $0 --release-name oc-marc --cluster au01-0 --timeout 45m
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
        -r|--release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -p|--pvc-name)
            PVC_NAME="$2"
            shift 2
            ;;
        -c|--cluster)
            BACKUP_CLUSTER="$2"
            shift 2
            ;;
        -t|--timeout)
            WAIT_TIMEOUT="$2"
            shift 2
            ;;
        --no-wait)
            WAIT_FOR_COMPLETION=false
            shift
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

detect_cluster_id() {
    local context_name context_basename

    context_basename="$(basename "$KUBECONFIG_PATH")"
    context_basename="${context_basename%.yaml}"
    context_basename="${context_basename%.yml}"

    if [ -n "$context_basename" ] && [ "$context_basename" != "." ] && [ "$context_basename" != ".." ]; then
        echo "$context_basename"
        return
    fi

    export_kubeconfig
    context_name="$(kubectl config current-context 2>/dev/null || true)"
    if [ -z "$context_name" ]; then
        echo "au01-0"
        return
    fi

    printf '%s\n' "$context_name" | sed 's#.*/##'
}

check_prerequisites() {
    log_step "Checking prerequisites"

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

    if [ -z "$RELEASE_NAME" ]; then
        echo -n "Enter OpenClaw release name: "
        read -r input
        RELEASE_NAME="$input"
    fi

    echo -n "Enter namespace [$NAMESPACE]: "
    read -r input
    if [ -n "${input:-}" ]; then
        NAMESPACE="$input"
    fi

    if [ -z "$BACKUP_CLUSTER" ]; then
        BACKUP_CLUSTER="$(detect_cluster_id)"
    fi

    echo -n "Enter backup cluster id [$BACKUP_CLUSTER]: "
    read -r input
    if [ -n "${input:-}" ]; then
        BACKUP_CLUSTER="$input"
    fi

    if [ -n "$PVC_NAME" ]; then
        echo -n "Enter PVC name [$PVC_NAME]: "
        read -r input
        if [ -n "${input:-}" ]; then
            PVC_NAME="$input"
        fi
    fi

    if [ -z "$RELEASE_NAME" ]; then
        log_error "Release name is required"
        exit 1
    fi
}

check_cluster_access() {
    log_step "Checking cluster access"
    export_kubeconfig
    kubectl get ns "$NAMESPACE" >/dev/null
}

check_backup_resources() {
    log_step "Checking backup resources"
    export_kubeconfig

    if ! kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" >/dev/null 2>&1; then
        log_error "Backup secret $SECRET_NAME not found in namespace $NAMESPACE"
        log_error "Run ./setup-pvc-backup.sh first."
        exit 1
    fi

    if ! kubectl get configmap -n "$NAMESPACE" "$SCRIPT_CONFIGMAP_NAME" >/dev/null 2>&1; then
        log_error "Backup script ConfigMap $SCRIPT_CONFIGMAP_NAME not found in namespace $NAMESPACE"
        log_error "Run ./setup-pvc-backup.sh first."
        exit 1
    fi
}

resolve_pvc_name() {
    local pvc_rows pvc_count

    log_step "Resolving PVC"
    export_kubeconfig

    if [ -n "$PVC_NAME" ]; then
        if ! kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" >/dev/null 2>&1; then
            log_error "PVC $PVC_NAME not found in namespace $NAMESPACE"
            exit 1
        fi
        return
    fi

    pvc_rows="$(kubectl get pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"
    pvc_rows="$(printf '%s\n' "$pvc_rows" | sed '/^$/d')"
    pvc_count="$(printf '%s\n' "$pvc_rows" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [ "$pvc_count" -eq 0 ]; then
        log_error "No PVCs found for release $RELEASE_NAME in namespace $NAMESPACE"
        exit 1
    fi

    if [ "$pvc_count" -gt 1 ]; then
        log_error "Multiple PVCs found for release $RELEASE_NAME"
        printf '%s\n' "$pvc_rows"
        log_error "Re-run with --pvc-name to choose one."
        exit 1
    fi

    PVC_NAME="$pvc_rows"
    log_info "Resolved PVC: $PVC_NAME"
}

create_backup_job() {
    local safe_instance

    log_step "Creating backup job"
    export_kubeconfig

    safe_instance="$(printf '%s' "$RELEASE_NAME" | tr -cs 'a-zA-Z0-9-' '-' | tr '[:upper:]' '[:lower:]' | sed 's/^-//; s/-$//' | cut -c1-20)"
    if [ -z "$safe_instance" ]; then
        safe_instance="unknown"
    fi

    job_name="openclaw-pvc-backup-${safe_instance}-$(date -u +%s)"
    JOB_NAME="$job_name"

    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: openclaw-pvc-backup
    app.kubernetes.io/component: backup
    app.kubernetes.io/part-of: openclaw
    app.kubernetes.io/instance: ${RELEASE_NAME}
    backup.openclaw.ai/pvc: ${PVC_NAME}
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 2
  activeDeadlineSeconds: 1800
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openclaw-pvc-backup
        app.kubernetes.io/component: backup
        app.kubernetes.io/instance: ${RELEASE_NAME}
        backup.openclaw.ai/pvc: ${PVC_NAME}
    spec:
      restartPolicy: OnFailure
      containers:
        - name: backup
          image: python:3.11-slim
          command: ["python3", "/scripts/openclaw-backup-s3.py"]
          envFrom:
            - secretRef:
                name: ${SECRET_NAME}
          env:
            - name: HOME
              value: /home/node
            - name: BACKUP_CLUSTER
              value: ${BACKUP_CLUSTER}
            - name: BACKUP_INSTANCE
              value: ${RELEASE_NAME}
            - name: BACKUP_PVC
              value: ${PVC_NAME}
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw
              readOnly: true
            - name: backup-script
              mountPath: /scripts
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
        - name: backup-script
          configMap:
            name: ${SCRIPT_CONFIGMAP_NAME}
EOF

    log_info "Created backup job $JOB_NAME for PVC $PVC_NAME"
}

wait_for_backup_job() {
    local pid_complete pid_failed winner status

    if [ "$WAIT_FOR_COMPLETION" != true ]; then
        return
    fi

    log_step "Waiting for backup job completion"
    export_kubeconfig

    kubectl wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout="$WAIT_TIMEOUT" >/tmp/"$JOB_NAME"-complete.log 2>&1 &
    pid_complete=$!
    kubectl wait --for=condition=failed job/"$JOB_NAME" -n "$NAMESPACE" --timeout="$WAIT_TIMEOUT" >/tmp/"$JOB_NAME"-failed.log 2>&1 &
    pid_failed=$!

    winner=""
    while true; do
        if ! kill -0 "$pid_complete" 2>/dev/null; then
            winner="complete"
            break
        fi
        if ! kill -0 "$pid_failed" 2>/dev/null; then
            winner="failed"
            break
        fi
        sleep 2
    done

    if [ "$winner" = "complete" ]; then
        status=0
        wait "$pid_complete" || status=$?
        kill "$pid_failed" 2>/dev/null || true
        wait "$pid_failed" 2>/dev/null || true

        if [ "$status" -eq 0 ]; then
            log_info "Backup job completed successfully"
            kubectl logs -n "$NAMESPACE" job/"$JOB_NAME"
            rm -f /tmp/"$JOB_NAME"-complete.log /tmp/"$JOB_NAME"-failed.log
            return
        fi
    else
        status=0
        wait "$pid_failed" || status=$?
        kill "$pid_complete" 2>/dev/null || true
        wait "$pid_complete" 2>/dev/null || true

        if [ "$status" -eq 0 ]; then
            log_error "Backup job failed."
            show_backup_job_diagnostics
            rm -f /tmp/"$JOB_NAME"-complete.log /tmp/"$JOB_NAME"-failed.log
            exit 1
        fi
    fi

    log_error "Backup job did not complete successfully within $WAIT_TIMEOUT"
    show_backup_job_diagnostics
    exit 1
}

show_backup_job_diagnostics() {
    export_kubeconfig

    kubectl describe job -n "$NAMESPACE" "$JOB_NAME" || true
    kubectl get pods -n "$NAMESPACE" -l "job-name=$JOB_NAME" -o wide || true
    kubectl logs -n "$NAMESPACE" job/"$JOB_NAME" || true
    kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 20 || true
}

show_next_steps() {
    echo ""
    log_info "Backup job created."
    echo ""
    echo "Job name: $JOB_NAME"
    echo "Release:  $RELEASE_NAME"
    echo "PVC:      $PVC_NAME"
    echo "Cluster:  $BACKUP_CLUSTER"
    echo ""
    echo "Check job status:"
    echo "  kubectl get job -n $NAMESPACE $JOB_NAME"
    echo ""
    echo "Watch logs:"
    echo "  kubectl logs -n $NAMESPACE job/$JOB_NAME -f"
    echo ""
}

main() {
    check_prerequisites
    prompt_inputs
    check_cluster_access
    check_backup_resources
    resolve_pvc_name
    create_backup_job
    wait_for_backup_job
    show_next_steps
}

main "$@"
