#!/bin/bash
#
# OpenClaw Deployment Script for Kubernetes
# Deploys OpenClaw AI assistant to au01-0 cluster
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"
RELEASE_NAME="openclaw"
EXISTING_PVC=""
HELM_REPO="openclaw-community"
HELM_REPO_URL="https://serhanekicii.github.io/openclaw-helm"
SECRET_NAME="${RELEASE_NAME}-env-secret"
VALUES_FILE="/tmp/${RELEASE_NAME}-values.yaml"
RENDERED_CONFIG_JSON="/tmp/${RELEASE_NAME}-openclaw.json"
OPENCLAW_CONFIG_TEMPLATE="openclaw/openclaw.json"
GATEWAY_AUTH_TOKEN=""
OLLAMA_EMBEDDINGS_MODEL="${OLLAMA_EMBEDDINGS_MODEL:-nomic-embed-text}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

Deploys OpenClaw to Kubernetes.

Options:
  -r, --release-name NAME   Release/instance name to deploy
  -p, --existing-pvc NAME   Use an existing PVC for persistence.data
  -h, --help                Show this help

Examples:
  $0
  $0 --release-name oc-sm
  $0 --release-name oc-sm-restore --existing-pvc oc-sm-restore-data
EOF

}

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -p|--existing-pvc)
            EXISTING_PVC="$2"
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install Helm."
        exit 1
    fi

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig not found at $KUBECONFIG_PATH"
        exit 1
    fi

    log_info "Prerequisites check passed."
}

check_cluster_disk_pressure() {
    local disk_pressure_nodes

    log_info "Checking cluster for disk pressure..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    disk_pressure_nodes=$(kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints --no-headers | grep 'node.kubernetes.io/disk-pressure' || true)

    if [ -n "$disk_pressure_nodes" ]; then
        log_error "Cluster has node(s) under disk pressure:"
        echo "$disk_pressure_nodes"
        log_error "Clear disk pressure before deploying a new OpenClaw instance."
        exit 1
    fi
}

# Prompt for API key
get_release_name() {
    local input_name
    local use_existing_pvc
    local release_name_from_args=false

    if [ -n "$RELEASE_NAME" ] && [ "$RELEASE_NAME" != "openclaw" ]; then
        release_name_from_args=true
        log_info "Using instance name from arguments: $RELEASE_NAME"
    else
        if [ -n "$EXISTING_PVC" ]; then
            RELEASE_NAME="$EXISTING_PVC"
        fi

        echo ""
        echo -n "Enter instance name [$RELEASE_NAME]: "
        read -r input_name

        if [ -n "$input_name" ]; then
            RELEASE_NAME="$input_name"
        fi
    fi

    if [ -z "$RELEASE_NAME" ]; then
        log_error "Instance name cannot be empty."
        exit 1
    fi

    SECRET_NAME="${RELEASE_NAME}-env-secret"
    VALUES_FILE="/tmp/${RELEASE_NAME}-values.yaml"
    RENDERED_CONFIG_JSON="/tmp/${RELEASE_NAME}-openclaw.json"

    if [ -z "$EXISTING_PVC" ]; then
        echo -n "Use an existing PVC for data? [y/N]: "
        read -r use_existing_pvc

        if [[ "${use_existing_pvc:-N}" =~ ^[Yy]$ ]]; then
            echo -n "Enter existing PVC name: "
            read -r EXISTING_PVC

            if [ -z "$EXISTING_PVC" ]; then
                log_error "Existing PVC name cannot be empty when enabled."
                exit 1
            fi

            if [ "$release_name_from_args" = false ] && [ "$RELEASE_NAME" = "openclaw" ]; then
                RELEASE_NAME="$EXISTING_PVC"
                SECRET_NAME="${RELEASE_NAME}-env-secret"
                VALUES_FILE="/tmp/${RELEASE_NAME}-values.yaml"
                RENDERED_CONFIG_JSON="/tmp/${RELEASE_NAME}-openclaw.json"
                log_info "Defaulting release name to existing PVC name: $RELEASE_NAME"
            fi
        fi
    fi
}

check_existing_pvc() {
    if [ -z "$EXISTING_PVC" ]; then
        return
    fi

    log_info "Using existing PVC for data persistence: $EXISTING_PVC"

    export KUBECONFIG="$KUBECONFIG_PATH"

    if ! kubectl get pvc "$EXISTING_PVC" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Existing PVC $EXISTING_PVC not found in namespace $NAMESPACE"
        exit 1
    fi
}

delete_release_configmaps() {
    export KUBECONFIG="$KUBECONFIG_PATH"

    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-config" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-scripts" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-startup-script" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-ms-graph-plugin" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-jira-plugin" --ignore-not-found
    kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-pod-delegate-plugin" --ignore-not-found
}

helm_release_exists() {
    export KUBECONFIG="$KUBECONFIG_PATH"
    helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1
}

delete_existing_release_pvcs() {
    local pvc_names
    local confirm_delete
    local pvc_name

    export KUBECONFIG="$KUBECONFIG_PATH"

    pvc_names=$(kubectl get pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o name 2>/dev/null || true)

    if [ -z "$pvc_names" ]; then
        return
    fi

    log_warn "Existing PersistentVolumeClaim(s) found for release '$RELEASE_NAME':"
    echo "$pvc_names"
    log_warn "These PVCs will be deleted before deployment continues."
    echo -n "Delete these PVCs and continue? [Y/n]: "
    read -r confirm_delete

    if [[ "${confirm_delete:-Y}" =~ ^[Nn]$ ]]; then
        log_error "Deployment cancelled because existing PVCs were not approved for deletion."
        exit 1
    fi

    if helm_release_exists; then
        log_warn "Existing Helm release found for '$RELEASE_NAME'. Uninstalling before PVC deletion..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
        kubectl wait --for=delete pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=180s || true
    fi

    delete_release_configmaps

    kubectl delete -n "$NAMESPACE" $pvc_names

    for pvc_name in $pvc_names; do
        kubectl wait --for=delete "$pvc_name" -n "$NAMESPACE" --timeout=180s || true
    done
}

validate_generated_config() {
    log_info "Validating generated openclaw.json..."

    python3 - <<PY
from pathlib import Path
import json

rendered_config_path = Path(${RENDERED_CONFIG_JSON@Q})
json.loads(Path(rendered_config_path).read_text())
print(rendered_config_path)
PY
}

render_openclaw_config() {
    local pod_delegate_targets_json="$1"

    log_info "Rendering openclaw.json from template..."

    python3 - <<PY
from pathlib import Path
import json
import re

template_path = Path(${OPENCLAW_CONFIG_TEMPLATE@Q})
rendered_config_path = Path(${RENDERED_CONFIG_JSON@Q})
template = template_path.read_text()
pod_delegate_targets_json = ${pod_delegate_targets_json@Q}
json.loads(pod_delegate_targets_json)
replacements = {
    "__GATEWAY_AUTH_TOKEN_JSON__": json.dumps(${GATEWAY_AUTH_TOKEN@Q}),
    "__MSGRAPH_TENANT_ID_JSON__": json.dumps(${MSGRAPH_TENANT_ID@Q}),
    "__MSGRAPH_CLIENT_ID_JSON__": json.dumps(${MSGRAPH_CLIENT_ID@Q}),
    "__JIRA_BASE_URL_JSON__": json.dumps(${JIRA_BASE_URL@Q}),
    "__OLLAMA_EMBEDDINGS_MODEL_JSON__": json.dumps(${OLLAMA_EMBEDDINGS_MODEL@Q}),
    "__POD_DELEGATE_TARGETS_JSON__": pod_delegate_targets_json,
}
rendered = template
for placeholder, value in replacements.items():
    rendered = rendered.replace(placeholder, value)
leftovers = sorted(set(re.findall(r"__[A-Z0-9_]+__", rendered)))
if leftovers:
    raise SystemExit(f"Unrendered placeholders remain: {leftovers}")
json.loads(rendered)
rendered_config_path.write_text(rendered + "\n")
PY
}

# Prompt for AWS Bedrock credentials
get_bedrock_credentials() {
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
        log_info "Using AWS_ACCESS_KEY_ID from environment"
    else
        echo ""
        echo -n "Enter your AWS Access Key ID: "
        read -r AWS_ACCESS_KEY_ID
    fi

    if [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        log_info "Using AWS_SECRET_ACCESS_KEY from environment"
    else
        echo -n "Enter your AWS Secret Access Key: "
        read -r AWS_SECRET_ACCESS_KEY
    fi

    AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

    if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
        log_error "AWS_ACCESS_KEY_ID is required"
        exit 1
    fi

    if [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        log_error "AWS_SECRET_ACCESS_KEY is required"
        exit 1
    fi

}

# Prompt for Microsoft Graph app identifiers
get_msgraph_config() {
    if [ -n "${MSGRAPH_TENANT_ID:-}" ]; then
        log_info "Using MSGRAPH_TENANT_ID from environment"
    else
        echo ""
        echo -n "Enter your Microsoft Graph Tenant ID: "
        read -r MSGRAPH_TENANT_ID
    fi

    if [ -n "${MSGRAPH_CLIENT_ID:-}" ]; then
        log_info "Using MSGRAPH_CLIENT_ID from environment"
    else
        echo -n "Enter your Microsoft Graph Client ID: "
        read -r MSGRAPH_CLIENT_ID
    fi

    if [ -z "${MSGRAPH_TENANT_ID:-}" ]; then
        log_error "MSGRAPH_TENANT_ID is required"
        exit 1
    fi

    if [ -z "${MSGRAPH_CLIENT_ID:-}" ]; then
        log_error "MSGRAPH_CLIENT_ID is required"
        exit 1
    fi
}

# Prompt for Jira base URL
get_jira_config() {
    local default_jira_url="https://dame-technologies.atlassian.net/"

    if [ -n "${JIRA_BASE_URL:-}" ]; then
        log_info "Using JIRA_BASE_URL from environment"
    else
        echo ""
        echo -n "Enter Jira base URL [$default_jira_url]: "
        read -r JIRA_BASE_URL
    fi

    JIRA_BASE_URL="${JIRA_BASE_URL:-$default_jira_url}"
    JIRA_BASE_URL="${JIRA_BASE_URL%/}"

    if [ -z "${JIRA_BASE_URL:-}" ]; then
        log_error "JIRA_BASE_URL cannot be empty"
        exit 1
    fi
}

# Setup Helm repository
setup_helm_repo() {
    log_info "Setting up Helm repository..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    if helm repo list | grep -q "$HELM_REPO"; then
        log_info "Helm repo already exists, updating..."
        helm repo update
    else
        log_info "Adding Helm repository..."
        helm repo add "$HELM_REPO" "$HELM_REPO_URL"
        helm repo update
    fi
}

# Create namespace
create_namespace() {
    log_info "Creating namespace '$NAMESPACE'..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

# Create AWS Bedrock credentials secret
create_secret() {
    log_info "Creating AWS Bedrock credentials secret..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found

    local aws_session_token_line=""
    if [ -n "$AWS_SESSION_TOKEN" ]; then
        aws_session_token_line="  AWS_SESSION_TOKEN: \"$AWS_SESSION_TOKEN\""
    fi

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_REGION: "ap-southeast-2"
$aws_session_token_line
EOF
}

# Create values file
create_values() {
    log_info "Creating Helm values file..."

    local persistence_data_block
    local pod_delegate_targets_json
    pod_delegate_targets_json="${POD_DELEGATE_TARGETS_JSON:-}"
    if [ -z "$pod_delegate_targets_json" ]; then
        pod_delegate_targets_json='{}'
    fi

    render_openclaw_config "$pod_delegate_targets_json"

    if [ -n "$EXISTING_PVC" ]; then
        persistence_data_block=$(cat <<EOF
    data:
      enabled: false
    restored-data:
      enabled: true
      type: persistentVolumeClaim
      existingClaim: $EXISTING_PVC
      globalMounts:
        - path: /home/node/.openclaw
EOF
)
    else
        persistence_data_block=$(cat <<EOF
    data:
      enabled: true
      type: persistentVolumeClaim
      accessMode: ReadWriteOnce
      size: 5Gi
      storageClass: talos-hostpath
EOF
)
    fi

    cat > "$VALUES_FILE" <<EOF
fullnameOverride: $RELEASE_NAME

app-template:
  controllers:
    main:
      initContainers:
        init-config:
          env:
            CONFIG_MODE: replace
      containers:
        main:
          command:
            - /bin/sh
            - -c
            - /bin/sh /startup-scripts/start-openclaw.sh
          # Bind to the pod network so Kubernetes probes can reach the gateway
          # Reference the secret containing the Bedrock credentials
          env:
            NODE_OPTIONS: "--max-old-space-size=2048"
          envFrom:
            - secretRef:
                name: $SECRET_NAME
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 4000m
              memory: 4Gi

  configMaps:
    config:
      data:
        openclaw.json: |
$(sed 's/^/          /' "$RENDERED_CONFIG_JSON")
    ms-graph-plugin:
      data:
        package.json: |
$(sed 's/^/          /' openclaw/plugins/ms-graph-query/package.json)
        openclaw.plugin.json: |
$(sed 's/^/          /' openclaw/plugins/ms-graph-query/openclaw.plugin.json)
        index.js: |
$(sed 's/^/          /' openclaw/plugins/ms-graph-query/index.js)
    jira-plugin:
      data:
        package.json: |
$(sed 's/^/          /' openclaw/plugins/jira-query/package.json)
        openclaw.plugin.json: |
$(sed 's/^/          /' openclaw/plugins/jira-query/openclaw.plugin.json)
        index.js: |
$(sed 's/^/          /' openclaw/plugins/jira-query/index.js)
    pod-delegate-plugin:
      data:
        package.json: |
$(sed 's/^/          /' openclaw/plugins/pod-delegate/package.json)
        openclaw.plugin.json: |
$(sed 's/^/          /' openclaw/plugins/pod-delegate/openclaw.plugin.json)
        index.js: |
$(sed 's/^/          /' openclaw/plugins/pod-delegate/index.js)
    bootstrap-doc:
      data:
        BOOTSTRAP.md: |
$(sed 's/^/          /' openclaw/workspace/BOOTSTRAP.md)
    startup-script:
      data:
        start-openclaw.sh: |
          #!/bin/sh
          set -eu

          BOOTSTRAP_FILE="/home/node/.openclaw/workspace/BOOTSTRAP.md"
          BOOTSTRAP_SOURCE="/bootstrap-source/BOOTSTRAP.md"
          BOOTSTRAP_VERSION_FILE="/home/node/.openclaw/workspace/.bootstrap-version"

          mkdir -p /home/node/.openclaw/workspace
          mkdir -p /home/node/.openclaw/plugins/ms-graph-query
          mkdir -p /home/node/.openclaw/plugins/jira-query
          mkdir -p /home/node/.openclaw/plugins/pod-delegate
          cp /plugin-source-ms-graph/package.json /home/node/.openclaw/plugins/ms-graph-query/package.json
          cp /plugin-source-ms-graph/openclaw.plugin.json /home/node/.openclaw/plugins/ms-graph-query/openclaw.plugin.json
          cp /plugin-source-ms-graph/index.js /home/node/.openclaw/plugins/ms-graph-query/index.js
          cp /plugin-source-jira/package.json /home/node/.openclaw/plugins/jira-query/package.json
          cp /plugin-source-jira/openclaw.plugin.json /home/node/.openclaw/plugins/jira-query/openclaw.plugin.json
          cp /plugin-source-jira/index.js /home/node/.openclaw/plugins/jira-query/index.js
          cp /plugin-source-pod-delegate/package.json /home/node/.openclaw/plugins/pod-delegate/package.json
          cp /plugin-source-pod-delegate/openclaw.plugin.json /home/node/.openclaw/plugins/pod-delegate/openclaw.plugin.json
          cp /plugin-source-pod-delegate/index.js /home/node/.openclaw/plugins/pod-delegate/index.js

          DEPLOYED_BOOTSTRAP_HASH="$(cat "\$BOOTSTRAP_VERSION_FILE" 2>/dev/null || true)"
          BOOTSTRAP_SOURCE_HASH="$(sha256sum "\$BOOTSTRAP_SOURCE" | awk '{print $1}')"
          if [ ! -f "\$BOOTSTRAP_FILE" ] || [ "\$BOOTSTRAP_SOURCE_HASH" != "\$DEPLOYED_BOOTSTRAP_HASH" ]; then
            cp "\$BOOTSTRAP_SOURCE" "\$BOOTSTRAP_FILE"
            printf '%s\n' "\$BOOTSTRAP_SOURCE_HASH" > "\$BOOTSTRAP_VERSION_FILE"
          fi

          exec openclaw gateway --bind lan --port 18789

  # Use the Talos hostpath storage class
  persistence:
${persistence_data_block}
    ms-graph-plugin:
      enabled: true
      type: configMap
      name: '{{ .Release.Name }}-ms-graph-plugin'
      globalMounts:
        - path: /plugin-source-ms-graph
          readOnly: true
    jira-plugin:
      enabled: true
      type: configMap
      name: '{{ .Release.Name }}-jira-plugin'
      globalMounts:
        - path: /plugin-source-jira
          readOnly: true
    pod-delegate-plugin:
      enabled: true
      type: configMap
      name: '{{ .Release.Name }}-pod-delegate-plugin'
      globalMounts:
        - path: /plugin-source-pod-delegate
          readOnly: true
    bootstrap-doc:
      enabled: true
      type: configMap
      name: '{{ .Release.Name }}-bootstrap-doc'
      globalMounts:
        - path: /bootstrap-source
          readOnly: true
    startup-script:
      enabled: true
      type: configMap
      name: '{{ .Release.Name }}-startup-script'
      globalMounts:
        - path: /startup-scripts
          readOnly: true
EOF

    validate_generated_config
}

show_deploy_diagnostics() {
    local pod_name

    log_warn "Helm deployment did not become ready. Gathering diagnostics..."

    helm status "$RELEASE_NAME" -n "$NAMESPACE" || true
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o wide || true
    kubectl describe deployment "$RELEASE_NAME" -n "$NAMESPACE" || true

    pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$pod_name" ]; then
        kubectl describe pod -n "$NAMESPACE" "$pod_name" || true
    fi
}

# Deploy OpenClaw
deploy_openclaw() {
    log_info "Deploying OpenClaw..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    if helm_release_exists; then
        log_warn "OpenClaw is already installed. Upgrading..."
        if ! helm upgrade "$RELEASE_NAME" "$HELM_REPO/openclaw" \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE" \
            --wait \
            --timeout 10m; then
            show_deploy_diagnostics
            exit 1
        fi
    else
        if ! helm install "$RELEASE_NAME" "$HELM_REPO/openclaw" \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE" \
            --wait \
            --timeout 10m; then
            show_deploy_diagnostics
            exit 1
        fi
    fi
}

ensure_gateway_auth_token() {
    local current_token

    log_info "Preserving existing gateway token or generating a new one..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    current_token=$(kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | python3 -c 'import json,sys; data=sys.stdin.read().strip(); print(json.loads(data).get("gateway", {}).get("auth", {}).get("token", "") if data else "")' || true)

    if [ -n "$current_token" ]; then
        GATEWAY_AUTH_TOKEN="$current_token"
        return
    fi

    GATEWAY_AUTH_TOKEN=$(python3 - <<'PY'
import secrets

print(secrets.token_urlsafe(32))
PY
)
}

apply_rendered_openclaw_config() {
    local pod_name
    local current_hash
    local rendered_hash

    log_info "Overwriting /home/node/.openclaw/openclaw.json in pod with rendered config..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod_name" ]; then
        log_error "Could not determine pod name for release '$RELEASE_NAME'"
        exit 1
    fi

    current_hash=$(kubectl exec -n "$NAMESPACE" "$pod_name" -c main -- sh -c 'sha256sum /home/node/.openclaw/openclaw.json 2>/dev/null | awk '\''{print $1}'\''' || true)
    rendered_hash=$(sha256sum "$RENDERED_CONFIG_JSON" | awk '{print $1}')

    if [ -n "$current_hash" ] && [ "$current_hash" = "$rendered_hash" ]; then
        log_info "Rendered openclaw.json already matches pod config. Skipping overwrite."
        return
    fi

    kubectl cp "$RENDERED_CONFIG_JSON" "$NAMESPACE/$pod_name:/home/node/.openclaw/openclaw.json" -c main
}

# Get gateway token
get_gateway_token() {
    log_info "Retrieving gateway token..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    # Wait for pod to be ready
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s || true

    sleep 5

    GATEWAY_TOKEN=$(kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | python3 -c 'import json,sys; data=sys.stdin.read().strip(); print(json.loads(data).get("gateway", {}).get("auth", {}).get("token", "") if data else "")')

    if [ -n "$GATEWAY_TOKEN" ]; then
        echo ""
        log_info "Gateway Token: $GATEWAY_TOKEN"
        echo ""
    else
        log_warn "Could not retrieve gateway token. Check logs after deployment."
    fi
}

# Display access instructions
show_access_info() {
    echo ""
    echo "============================================"
    log_info "OpenClaw deployed successfully! 🦞"
    echo "============================================"
    echo ""
    echo "To access OpenClaw:"
    echo "1. Start port forwarding:"
    echo "   export KUBECONFIG=$KUBECONFIG_PATH"
    echo "   kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME 18789:18789"
    echo ""
    echo "2. Open in browser: http://localhost:18789"
    echo "3. Authenticate with the gateway token shown above"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -c main -f"
    echo ""
}

# Main execution
main() {
    log_info "Starting OpenClaw deployment..."

    check_prerequisites
    check_cluster_disk_pressure
    get_release_name
    check_existing_pvc
    get_bedrock_credentials
    get_msgraph_config
    get_jira_config
    setup_helm_repo
    create_namespace
    ensure_gateway_auth_token
    delete_existing_release_pvcs
    create_secret
    create_values
    deploy_openclaw
    apply_rendered_openclaw_config
    get_gateway_token
    show_access_info
}

# Run main function
main
