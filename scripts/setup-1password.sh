#!/bin/bash
#
# setup-1password.sh — Configure 1Password service account for OpenClaw secrets
#
# Prerequisites:
#   - kubectl access to the openclaw namespace
#   - A 1Password service account token
#   - op CLI installed (for local testing)
#
# Usage:
#   ./scripts/setup-1password.sh
#   ./scripts/setup-1password.sh --token "ops_eyJ..."
#   OP_SERVICE_ACCOUNT_TOKEN="ops_eyJ..." ./scripts/setup-1password.sh
#

set -e

KUBECONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/au01-0.yaml}"
NAMESPACE="openclaw"
SECRET_NAME="openclaw-1password"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --token) OP_TOKEN="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    *) log_error "Unknown arg: $1"; exit 1 ;;
  esac
done

# Resolve token
OP_TOKEN="${OP_TOKEN:-$OP_SERVICE_ACCOUNT_TOKEN}"
if [ -z "$OP_TOKEN" ]; then
  echo -n "Enter 1Password service account token (ops_...): "
  read -rs OP_TOKEN
  echo
fi

if [[ ! "$OP_TOKEN" =~ ^ops_ ]]; then
  log_error "Token must start with 'ops_'"
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Create/update the k8s secret
log_info "Creating Kubernetes secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=OP_SERVICE_ACCOUNT_TOKEN="$OP_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

log_info "Secret '${SECRET_NAME}' created/updated."

# Check if deployment exists and patch it
if kubectl get deployment openclaw -n "$NAMESPACE" &>/dev/null; then
  log_info "Patching OpenClaw deployment to mount 1Password secret..."

  # Check if envFrom already references the secret
  EXISTING=$(kubectl get deployment openclaw -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].envFrom}' 2>/dev/null || echo "")

  if echo "$EXISTING" | grep -q "$SECRET_NAME"; then
    log_info "Deployment already references ${SECRET_NAME}, skipping patch."
  else
    kubectl patch deployment openclaw -n "$NAMESPACE" --type=json -p="[
      {
        \"op\": \"add\",
        \"path\": \"/spec/template/spec/containers/0/envFrom/-\",
        \"value\": {
          \"secretRef\": {
            \"name\": \"${SECRET_NAME}\"
          }
        }
      }
    ]"
    log_info "Deployment patched. Pod will restart with 1Password token available."
  fi
else
  log_warn "OpenClaw deployment not found. Add the secret reference to your Helm values (see below)."
fi

echo ""
echo "============================================"
log_info "1Password setup complete! 🔐"
echo "============================================"
echo ""
echo "The OP_SERVICE_ACCOUNT_TOKEN is now available as an env var in the pod."
echo ""
echo "Next steps:"
echo "  1. Verify the pod restarted:  kubectl get pods -n ${NAMESPACE}"
echo "  2. Exec into pod and test:    kubectl exec -n ${NAMESPACE} deploy/openclaw -c main -- op vault list"
echo "  3. Configure OpenClaw secrets: kubectl exec -n ${NAMESPACE} deploy/openclaw -c main -- openclaw secrets configure"
echo ""
echo "Or add to your Helm values permanently (see helm/values-1password.yaml)"
echo ""
