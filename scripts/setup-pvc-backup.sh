#!/bin/bash
#
# setup-pvc-backup.sh — Deploy the OpenClaw PVC backup CronJob to Kubernetes
#
# Creates the required AWS credentials Secret and backup script ConfigMap,
# then applies the CronJob manifest. Idempotent — safe to re-run.
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - AWS credentials with s3:PutObject on the backup bucket
#
# Credentials can be supplied via:
#   a) Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_BUCKET)
#   b) 1Password (if OP_SERVICE_ACCOUNT_TOKEN is set) — fetched automatically
#   c) Interactive prompt as a fallback
#
# Usage:
#   ./scripts/setup-pvc-backup.sh
#   ./scripts/setup-pvc-backup.sh --dry-run     # print manifests, no apply
#   ./scripts/setup-pvc-backup.sh --namespace my-ns
#   ./scripts/setup-pvc-backup.sh --trigger     # also fire a manual job to test
#

set -euo pipefail

# ── Defaults ───────────────────────────────────────────────────────
NAMESPACE="${NAMESPACE:-openclaw}"
REGION="${AWS_REGION:-ap-southeast-2}"
BUCKET="${S3_BUCKET:-dame-openclaw-backup}"
BACKUP_PREFIX="${BACKUP_PREFIX:-openclaw-backups/au01-0}"
KUBECONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/au01-0.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CRONJOB_MANIFEST="$REPO_ROOT/k8s/pvc-backup-cronjob.yaml"
BACKUP_SCRIPT="$SCRIPT_DIR/openclaw-backup-s3.py"
OP_BIN="${HOME}/.openclaw/bin/op"
OP_VAULT="Infrastructure"
OP_ITEM="aws-backup"
DRY_RUN=false
TRIGGER=false

# ── Helpers ────────────────────────────────────────────────────────
log()     { echo "[pvc-backup-setup] $*"; }
warn()    { echo "[pvc-backup-setup] WARN: $*" >&2; }
err()     { echo "[pvc-backup-setup] ERROR: $*" >&2; }
die()     { err "$*"; exit 1; }
success() { echo "[pvc-backup-setup] ✓ $*"; }

kubectl_cmd() {
    if [ -f "$KUBECONFIG_PATH" ]; then
        KUBECONFIG="$KUBECONFIG_PATH" kubectl "$@"
    else
        kubectl "$@"
    fi
}

# ── Args ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)    DRY_RUN=true ;;
        --trigger)    TRIGGER=true ;;
        --namespace)  NAMESPACE="$2"; shift ;;
        --namespace=*) NAMESPACE="${1#*=}" ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

# ── Preflight ──────────────────────────────────────────────────────
log "Preflight checks..."

command -v kubectl &>/dev/null || die "kubectl not found"
[ -f "$CRONJOB_MANIFEST" ]    || die "CronJob manifest not found: $CRONJOB_MANIFEST"
[ -f "$BACKUP_SCRIPT" ]       || die "Backup script not found: $BACKUP_SCRIPT"

if $DRY_RUN; then
    log "DRY RUN mode — no resources will be created or modified"
fi

# ── Resolve AWS credentials ────────────────────────────────────────
log "Resolving AWS credentials..."

ACCESS_KEY="${AWS_ACCESS_KEY_ID:-}"
SECRET_KEY="${AWS_SECRET_ACCESS_KEY:-}"

# Try 1Password if credentials not already in env
if { [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; } && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    OP=""
    if [ -x "$OP_BIN" ]; then
        OP="$OP_BIN"
    elif command -v op &>/dev/null; then
        OP="op"
    fi

    if [ -n "$OP" ] && $OP whoami &>/dev/null 2>&1; then
        log "Fetching AWS credentials from 1Password (vault: $OP_VAULT, item: $OP_ITEM)..."
        _creds=$($OP item get "$OP_ITEM" --vault "$OP_VAULT" --format json 2>/dev/null || true)
        if [ -n "$_creds" ]; then
            ACCESS_KEY=$(echo "$_creds" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['value']) for f in d.get('fields',[]) if f.get('label') in ('aws_access_key_id','username')]" 2>/dev/null | head -1 || true)
            SECRET_KEY=$(echo "$_creds" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['value']) for f in d.get('fields',[]) if f.get('label') in ('aws_secret_access_key','password','credential')]" 2>/dev/null | head -1 || true)
            BUCKET=$(echo "$_creds" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['value']) for f in d.get('fields',[]) if f.get('label') == 'bucket']" 2>/dev/null | head -1 || BUCKET)
            REGION=$(echo "$_creds" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['value']) for f in d.get('fields',[]) if f.get('label') == 'region']" 2>/dev/null | head -1 || REGION)
            [ -n "$ACCESS_KEY" ] && log "Credentials retrieved from 1Password"
        fi
    fi
fi

# Try the credentials file on PVC as fallback
CRED_FILE="${HOME}/.openclaw/credentials/credentials/aws-backup.json"
if { [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; } && [ -f "$CRED_FILE" ]; then
    log "Reading credentials from $CRED_FILE..."
    ACCESS_KEY=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('aws_access_key_id',''))" 2>/dev/null || true)
    SECRET_KEY=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('aws_secret_access_key',''))" 2>/dev/null || true)
    BUCKET=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('bucket','$BUCKET'))" 2>/dev/null || echo "$BUCKET")
    REGION=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('region','$REGION'))" 2>/dev/null || echo "$REGION")
fi

# Interactive fallback
if [ -z "$ACCESS_KEY" ]; then
    echo -n "AWS Access Key ID: "
    read -r ACCESS_KEY
fi
if [ -z "$SECRET_KEY" ]; then
    echo -n "AWS Secret Access Key: "
    read -r -s SECRET_KEY
    echo
fi
if [ -z "$BUCKET" ]; then
    echo -n "S3 Bucket name: "
    read -r BUCKET
fi

[ -n "$ACCESS_KEY" ] || die "AWS_ACCESS_KEY_ID is required"
[ -n "$SECRET_KEY" ] || die "AWS_SECRET_ACCESS_KEY is required"
[ -n "$BUCKET" ]     || die "S3_BUCKET is required"

log "Bucket:  $BUCKET"
log "Region:  $REGION"
log "Prefix:  $BACKUP_PREFIX"
log "Namespace: $NAMESPACE"

# ── Create namespace ───────────────────────────────────────────────
if ! $DRY_RUN; then
    kubectl_cmd create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl_cmd apply -f -
fi

# ── Create AWS credentials Secret ─────────────────────────────────
log "Creating Secret: openclaw-backup-aws..."
if $DRY_RUN; then
    cat <<EOF
--- # Secret: openclaw-backup-aws
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-backup-aws
  namespace: $NAMESPACE
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "<redacted>"
  AWS_SECRET_ACCESS_KEY: "<redacted>"
  AWS_REGION: "$REGION"
  S3_BUCKET: "$BUCKET"
  BACKUP_PREFIX: "$BACKUP_PREFIX"
EOF
else
    kubectl_cmd create secret generic openclaw-backup-aws \
        --namespace "$NAMESPACE" \
        --from-literal=AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
        --from-literal=AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
        --from-literal=AWS_REGION="$REGION" \
        --from-literal=S3_BUCKET="$BUCKET" \
        --from-literal=BACKUP_PREFIX="$BACKUP_PREFIX" \
        --dry-run=client -o yaml | kubectl_cmd apply -f -
    success "Secret openclaw-backup-aws"
fi

# ── Create backup script ConfigMap ────────────────────────────────
log "Creating ConfigMap: openclaw-backup-script..."
if $DRY_RUN; then
    log "  (would create ConfigMap from $BACKUP_SCRIPT)"
else
    kubectl_cmd create configmap openclaw-backup-script \
        --namespace "$NAMESPACE" \
        --from-file=openclaw-backup-s3.py="$BACKUP_SCRIPT" \
        --dry-run=client -o yaml | kubectl_cmd apply -f -
    success "ConfigMap openclaw-backup-script"
fi

# ── Apply CronJob manifest ─────────────────────────────────────────
log "Applying CronJob manifest: $CRONJOB_MANIFEST..."
if $DRY_RUN; then
    log "  (would apply $CRONJOB_MANIFEST)"
    echo ""
    cat "$CRONJOB_MANIFEST"
else
    kubectl_cmd apply -f "$CRONJOB_MANIFEST"
    success "CronJob openclaw-pvc-backup applied"
fi

# ── Verify ────────────────────────────────────────────────────────
if ! $DRY_RUN; then
    log ""
    log "Current state:"
    kubectl_cmd get cronjob openclaw-pvc-backup -n "$NAMESPACE"
fi

# ── Optional: trigger manual run ──────────────────────────────────
if $TRIGGER && ! $DRY_RUN; then
    log ""
    log "Triggering manual test run..."
    JOB_NAME="openclaw-pvc-backup-manual-$(date +%s)"
    kubectl_cmd create job "$JOB_NAME" \
        --from=cronjob/openclaw-pvc-backup \
        -n "$NAMESPACE"
    success "Job $JOB_NAME created"
    log ""
    log "Watch logs with:"
    log "  kubectl logs -n $NAMESPACE -l job-name=$JOB_NAME -f"
fi

# ── Done ───────────────────────────────────────────────────────────
log ""
log "PVC backup CronJob deployed. Runs daily at 02:00 UTC."
log ""
log "Useful commands:"
log "  kubectl get cronjob openclaw-pvc-backup -n $NAMESPACE"
log "  kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/name=openclaw-pvc-backup"
log "  kubectl create job openclaw-pvc-backup-manual --from=cronjob/openclaw-pvc-backup -n $NAMESPACE"
