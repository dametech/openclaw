#!/bin/bash
#
# OpenClaw Microsoft Teams Integration Setup Script
# Enables Teams for an existing OpenClaw release and configures ingress routing.
#

set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
RELEASE_NAME=""
TEAMS_PORT="3978"
TEAMS_PATH="/api/messages"
LOCAL_PLUGIN_DIR="openclaw/plugins/msteams"
POD_NAME=""
DEPLOYMENT_LABEL_NAME=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    echo "║   OpenClaw Microsoft Teams Setup             ║"
    echo "║   Enable Teams On Existing Release           ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

check_prerequisites() {
    log_step "Checking prerequisites"

    local missing=0
    for cmd in kubectl helm jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "$cmd not found"
            missing=1
        fi
    done

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_PATH"
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        exit 1
    fi
}

prompt_inputs() {
    log_step "Collecting release and Teams credentials"

    echo -n "Enter instance name: "
    read -r RELEASE_NAME

    if [ -z "$RELEASE_NAME" ]; then
        log_error "Release name cannot be empty"
        exit 1
    fi

    if [[ ! "$RELEASE_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        log_error "Release name must be DNS-safe: lowercase letters, numbers, hyphens"
        exit 1
    fi

    echo -n "Enter namespace [openclaw]: "
    read -r input_namespace
    if [ -n "${input_namespace:-}" ]; then
        NAMESPACE="$input_namespace"
    fi

    echo -n "Enter Azure app registration (client) ID: "
    read -r MSTEAMS_APP_ID

    echo -n "Enter Azure app registration client secret value: "
    read -r MSTEAMS_APP_PASSWORD

    echo -n "Enter Microsoft Entra tenant ID: "
    read -r MSTEAMS_TENANT_ID

    if [ -z "$MSTEAMS_APP_ID" ] || [ -z "$MSTEAMS_APP_PASSWORD" ] || [ -z "$MSTEAMS_TENANT_ID" ]; then
        log_error "Teams credentials cannot be empty"
        exit 1
    fi

    SECRET_NAME="${RELEASE_NAME}-teams-credentials"
    SERVICE_NAME="${RELEASE_NAME}-teams-webhook"
    INGRESS_NAME="${RELEASE_NAME}-teams-ingress"
    TEAMS_HOSTNAME="${RELEASE_NAME}.openclaw.dametech.net"
    TEAMS_WEBHOOK_URL="https://${TEAMS_HOSTNAME}/api/messages"
}

check_release_exists() {
    log_step "Checking target release"

    export KUBECONFIG="$KUBECONFIG_PATH"

    if ! kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Deployment $RELEASE_NAME not found in namespace $NAMESPACE"
        exit 1
    fi

    if ! kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" | tail -n +2 | grep -q .; then
        log_error "No pods found for release $RELEASE_NAME"
        exit 1
    fi

    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
        -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$POD_NAME" ]; then
        log_error "Failed to determine pod name for release $RELEASE_NAME"
        exit 1
    fi

    DEPLOYMENT_LABEL_NAME=$(kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.metadata.labels.app\.kubernetes\.io/name}')
    if [ -z "$DEPLOYMENT_LABEL_NAME" ]; then
        log_error "Failed to determine app.kubernetes.io/name label for deployment $RELEASE_NAME"
        exit 1
    fi
}

create_teams_secret() {
    log_step "Creating Teams credentials secret"

    export KUBECONFIG="$KUBECONFIG_PATH"

    kubectl create secret generic "$SECRET_NAME" \
        --namespace "$NAMESPACE" \
        --from-literal=MSTEAMS_APP_ID="$MSTEAMS_APP_ID" \
        --from-literal=MSTEAMS_APP_PASSWORD="$MSTEAMS_APP_PASSWORD" \
        --from-literal=MSTEAMS_TENANT_ID="$MSTEAMS_TENANT_ID" \
        --dry-run=client -o yaml | kubectl apply -f -
}

create_teams_service() {
    log_step "Creating Teams webhook service"

    export KUBECONFIG="$KUBECONFIG_PATH"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${RELEASE_NAME}-teams-webhook
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: ${DEPLOYMENT_LABEL_NAME}
    app.kubernetes.io/instance: $RELEASE_NAME
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: ${DEPLOYMENT_LABEL_NAME}
    app.kubernetes.io/instance: $RELEASE_NAME
  ports:
    - name: teams-webhook
      port: $TEAMS_PORT
      targetPort: $TEAMS_PORT
      protocol: TCP
EOF

    NODE_PORT=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
    if [ -z "$NODE_PORT" ]; then
        log_error "Failed to determine NodePort for $SERVICE_NAME"
        exit 1
    fi
}

ensure_plugin_installed() {
    log_step "Installing Teams plugin"

    export KUBECONFIG="$KUBECONFIG_PATH"

    if [ ! -f "$LOCAL_PLUGIN_DIR/openclaw.plugin.json" ] || [ ! -f "$LOCAL_PLUGIN_DIR/package.json" ]; then
        log_error "Local Teams plugin source not found under $LOCAL_PLUGIN_DIR"
        log_error "Expected vendored plugin files to be present before enabling Teams"
        exit 1
    fi

    kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \
        openclaw plugins list | grep -Fq 'msteams' && return

    kubectl exec -n "$NAMESPACE" "$POD_NAME" -c main -- rm -rf /tmp/openclaw-msteams-source
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -c main -- mkdir -p /tmp/openclaw-msteams-source
    kubectl cp "$LOCAL_PLUGIN_DIR/." "$NAMESPACE/$POD_NAME:/tmp/openclaw-msteams-source" -c main

    kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \
        openclaw plugins install /tmp/openclaw-msteams-source || {
        log_error "Local msteams plugin install failed"
        log_error "The runtime must be able to complete 'openclaw plugins install /tmp/openclaw-msteams-source' before Teams can be enabled"
        exit 1
    }
}

patch_openclaw_config() {
    log_step "Patching OpenClaw configuration"

    export KUBECONFIG="$KUBECONFIG_PATH"

    local current_json updated_json
    current_json=$(kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -- \
        cat /home/node/.openclaw/openclaw.json)

    updated_json=$(printf '%s' "$current_json" | jq \
        --arg appId "$MSTEAMS_APP_ID" \
        --arg appPassword "$MSTEAMS_APP_PASSWORD" \
        --arg tenantId "$MSTEAMS_TENANT_ID" \
        --argjson port "$TEAMS_PORT" \
        --arg path "$TEAMS_PATH" \
        '.channels.msteams.appId = $appId
        | .channels.msteams.appPassword = $appPassword
        | .channels.msteams.tenantId = $tenantId
        | .channels.msteams.enabled = true
        | .channels.msteams.webhook.port = $port
        | .channels.msteams.webhook.path = $path
        | .channels.msteams.dmPolicy = "open"
        | .channels.msteams.allowFrom = ["*"]
        | .channels.msteams.groupPolicy = "open"')

    printf '%s' "$updated_json" | kubectl exec -n "$NAMESPACE" deployment/"$RELEASE_NAME" -c main -i -- \
        sh -c 'cat > /home/node/.openclaw/openclaw.json'

    kubectl rollout restart deployment/"$RELEASE_NAME" -n "$NAMESPACE"
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=180s
}

create_teams_ingress() {
    log_step "Creating Teams ingress"

    export KUBECONFIG="$KUBECONFIG_PATH"

    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${RELEASE_NAME}-teams-ingress
  namespace: $NAMESPACE
spec:
  ingressClassName: nginx
  rules:
    - host: ${TEAMS_HOSTNAME}
      http:
        paths:
          - path: ${TEAMS_PATH}
            pathType: Prefix
            backend:
              service:
                name: ${RELEASE_NAME}-teams-webhook
                port:
                  number: ${TEAMS_PORT}
EOF
}

show_summary() {
    log_step "Teams enablement complete"

    echo "Release: $RELEASE_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Service: $SERVICE_NAME"
    echo "Secret: $SECRET_NAME"
    echo "Teams webhook URL: https://${TEAMS_HOSTNAME}/api/messages"
    echo ""
    echo "Set the Azure Bot messaging endpoint to:"
    echo "  https://${TEAMS_HOSTNAME}/api/messages"
    echo ""
    echo "To approve pending Teams pairing:"
    echo "  kubectl exec -n $NAMESPACE deployment/$RELEASE_NAME -c main -- \\"
    echo "    node dist/index.js pairing approve msteams <CODE>"
}

main() {
    show_banner
    check_prerequisites
    prompt_inputs
    check_release_exists
    create_teams_secret
    create_teams_service
    ensure_plugin_installed
    patch_openclaw_config
    create_teams_ingress
    show_summary
}

main "$@"
