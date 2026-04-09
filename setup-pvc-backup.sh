#!/bin/bash
#
# OpenClaw PVC Backup Setup Script
# Creates or updates the AWS secret, backup script ConfigMap, and CronJob manifest.
#

set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
BACKUP_CLUSTER=""
SECRET_NAME="openclaw-backup-aws"
SCRIPT_CONFIGMAP_NAME="openclaw-backup-script"
MANIFEST_PATH="k8s/pvc-backup-cronjob.yaml"
SCRIPT_SOURCE="scripts/openclaw-backup-s3.py"
CRONJOB_NAME="openclaw-pvc-backup-dispatcher"

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

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   OpenClaw PVC Backup Setup                  ║"
    echo "║   Secret, ConfigMap, and CronJob            ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Creates or updates the OpenClaw PVC backup secret, ConfigMap, and CronJob.

Options:
  -n, --namespace NAME         Kubernetes namespace (default: openclaw)
  -k, --kubeconfig PATH        Kubeconfig path (default: ~/.kube/au01-0.yaml)
  -c, --cluster NAME           Backup cluster id for S3 path (defaults to current kube context)
  -b, --bucket NAME            S3 bucket name
  -r, --region NAME            AWS region (default: ap-southeast-2)
  -a, --access-key KEY         AWS access key id
  -s, --secret-key KEY         AWS secret access key
  -h, --help                   Show this help

Examples:
  $0
  $0 --bucket dame-openclaw-backup
  $0 --bucket dame-openclaw-backup --access-key AKIA... --secret-key ... --region ap-southeast-2
EOF
}

AWS_REGION="ap-southeast-2"
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
S3_BUCKET="dame-openclaw-backup"

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
        -c|--cluster)
            BACKUP_CLUSTER="$2"
            shift 2
            ;;
        -b|--bucket)
            S3_BUCKET="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -a|--access-key)
            AWS_ACCESS_KEY_ID="$2"
            shift 2
            ;;
        -s|--secret-key)
            AWS_SECRET_ACCESS_KEY="$2"
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

check_prerequisites() {
    log_step "Checking prerequisites"

    local missing=0

    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found"
        missing=1
    fi

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_PATH"
        missing=1
    fi

    if [ ! -f "$MANIFEST_PATH" ]; then
        log_error "Manifest not found at $MANIFEST_PATH"
        missing=1
    fi

    if [ ! -f "$SCRIPT_SOURCE" ]; then
        log_error "Backup script not found at $SCRIPT_SOURCE"
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        exit 1
    fi
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

prompt_inputs() {
    log_step "Collecting backup configuration"

    if [ -z "$BACKUP_CLUSTER" ]; then
        BACKUP_CLUSTER="$(detect_cluster_id)"
    fi

    echo -n "Enter namespace [$NAMESPACE]: "
    read -r input_namespace
    if [ -n "${input_namespace:-}" ]; then
        NAMESPACE="$input_namespace"
    fi

    echo -n "Enter backup cluster id [$BACKUP_CLUSTER]: "
    read -r input_cluster
    if [ -n "${input_cluster:-}" ]; then
        BACKUP_CLUSTER="$input_cluster"
    fi

    echo -n "Enter S3 bucket name [$S3_BUCKET]: "
    read -r input_bucket
    if [ -n "${input_bucket:-}" ]; then
        S3_BUCKET="$input_bucket"
    fi

    if [ -z "$S3_BUCKET" ]; then
        echo -n "Enter S3 bucket name: "
        read -r S3_BUCKET
    fi

    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        echo -n "Enter AWS access key id: "
        read -r AWS_ACCESS_KEY_ID
    fi

    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo -n "Enter AWS secret access key: "
        read -r AWS_SECRET_ACCESS_KEY
    fi

    echo -n "Enter AWS region [$AWS_REGION]: "
    read -r input_region
    if [ -n "${input_region:-}" ]; then
        AWS_REGION="$input_region"
    fi

    if [ -z "$S3_BUCKET" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        log_error "Bucket, access key, and secret key are required"
        exit 1
    fi
}

export_kubeconfig() {
    export KUBECONFIG="$KUBECONFIG_PATH"
}

check_cluster_access() {
    log_step "Checking cluster access"
    export_kubeconfig
    kubectl get ns "$NAMESPACE" >/dev/null
}

check_existing_secret() {
    log_step "Checking existing AWS secret"
    export_kubeconfig

    if kubectl get secret -n "$NAMESPACE" "$SECRET_NAME" >/dev/null 2>&1; then
        log_warn "Secret $SECRET_NAME already exists in namespace $NAMESPACE"
        echo -n "Replace it with the supplied values? [Y/n]: "
        read -r replace_secret
        if [[ "${replace_secret:-Y}" =~ ^[Nn]$ ]]; then
            log_info "Keeping existing secret"
            SKIP_SECRET_UPDATE=true
        else
            SKIP_SECRET_UPDATE=false
        fi
    else
        SKIP_SECRET_UPDATE=false
    fi
}

create_or_update_secret() {
    if [ "${SKIP_SECRET_UPDATE:-false}" = true ]; then
        return
    fi

    log_step "Creating or updating AWS backup secret"
    export_kubeconfig

    kubectl create secret generic "$SECRET_NAME" \
        --namespace "$NAMESPACE" \
        --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        --from-literal=AWS_REGION="$AWS_REGION" \
        --from-literal=S3_BUCKET="$S3_BUCKET" \
        --dry-run=client -o yaml | kubectl apply -f -
}

create_or_update_script_configmap() {
    log_step "Creating or updating backup script ConfigMap"
    export_kubeconfig

    kubectl create configmap "$SCRIPT_CONFIGMAP_NAME" \
        --namespace "$NAMESPACE" \
        --from-file=openclaw-backup-s3.py="$SCRIPT_SOURCE" \
        --dry-run=client -o yaml | kubectl apply -f -
}

apply_manifest() {
    log_step "Applying PVC backup manifest"
    export_kubeconfig

    kubectl apply -f "$MANIFEST_PATH"
}

show_next_steps() {
    echo ""
    log_info "PVC backup resources are configured."
    echo ""
    echo "Check the CronJob:"
    echo "  kubectl get cronjob -n $NAMESPACE $CRONJOB_NAME"
    echo ""
    echo "Run it once manually:"
    echo "  kubectl create job --from=cronjob/openclaw-pvc-backup-dispatcher -n $NAMESPACE ${CRONJOB_NAME}-manual-\$(date +%s)"
    echo ""
    echo "Watch jobs:"
    echo "  kubectl get jobs -n $NAMESPACE"
    echo ""
    echo "The cluster-level backup path prefix will be:"
    echo "  openclaw-backups/$BACKUP_CLUSTER/<instance>/<pvc>/<timestamp>.tar.gz"
    echo ""
}

main() {
    show_banner
    check_prerequisites
    prompt_inputs
    check_cluster_access
    check_existing_secret
    create_or_update_secret
    create_or_update_script_configmap
    apply_manifest
    show_next_steps
}

main "$@"
