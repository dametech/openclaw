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
HELM_REPO="openclaw-community"
HELM_REPO_URL="https://serhanekicii.github.io/openclaw-helm"
SECRET_NAME="${RELEASE_NAME}-env-secret"
VALUES_FILE="/tmp/${RELEASE_NAME}-values.yaml"

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

    echo ""
    echo -n "Enter instance name [openclaw]: "
    read -r input_name

    if [ -n "$input_name" ]; then
        RELEASE_NAME="$input_name"
    fi

    if [ -z "$RELEASE_NAME" ]; then
        log_error "Instance name cannot be empty."
        exit 1
    fi

    SECRET_NAME="${RELEASE_NAME}-env-secret"
    VALUES_FILE="/tmp/${RELEASE_NAME}-values.yaml"
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

    cat > "$VALUES_FILE" <<EOF
app-template:
  controllers:
    main:
      containers:
        main:
          command:
            - /bin/sh
            - -c
            - /bin/sh /scripts/start-openclaw.sh
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
          {
            "gateway": {
              "mode": "local",
              "controlUi": {
                "allowedOrigins": [
                  "http://127.0.0.1:18789",
                  "http://localhost:18789"
                ]
              }
            },
            "agents": {
              "defaults": {
                "workspace": "/home/node/.openclaw/workspace",
                "model": {
                  "primary": "amazon-bedrock/global.anthropic.claude-sonnet-4-6"
                },
                "models": {
                  "amazon-bedrock/global.anthropic.claude-sonnet-4-6": {
                    "params": {
                      "cacheRetention": "ephemeral"
                    }
                  },
                  "amazon-bedrock/global.anthropic.claude-opus-4-6-v1": {
                    "params": {
                      "cacheRetention": "ephemeral"
                    }
                  },
                  "amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0": {
                    "params": {
                      "cacheRetention": "none"
                    }
                  }
                },
                "userTimezone": "Australia/Brisbane",
                "timeoutSeconds": 600,
                "maxConcurrent": 1
              },
              "list": [
                {
                  "id": "main",
                  "default": true,
                  "identity": {
                    "name": "OpenClaw",
                    "emoji": "🦞"
                  },
                  "model": "amazon-bedrock/global.anthropic.claude-sonnet-4-6"
                }
              ]
            },
            "models": {
              "providers": {
                "amazon-bedrock": {
                  "baseUrl": "https://bedrock-runtime.ap-southeast-2.amazonaws.com",
                  "apiKey": "aws-sdk",
                  "api": "bedrock-converse-stream",
                  "models": [
                    {
                      "id": "global.anthropic.claude-sonnet-4-6",
                      "name": "Claude Sonnet 4.6 (Bedrock)",
                      "api": "bedrock-converse-stream",
                      "reasoning": true,
                      "input": ["text", "image"],
                      "cost": {
                        "input": 3,
                        "output": 15,
                        "cacheRead": 0.3,
                        "cacheWrite": 3.75
                      },
                      "contextWindow": 200000,
                      "maxTokens": 8000
                    },
                    {
                      "id": "global.anthropic.claude-opus-4-6-v1",
                      "name": "Claude Opus 4.6 (Bedrock)",
                      "api": "bedrock-converse-stream",
                      "reasoning": true,
                      "input": ["text", "image"],
                      "cost": {
                        "input": 5,
                        "output": 25,
                        "cacheRead": 0.5,
                        "cacheWrite": 6.25
                      },
                      "contextWindow": 200000,
                      "maxTokens": 8000
                    },
                    {
                      "id": "global.anthropic.claude-haiku-4-5-20251001-v1:0",
                      "name": "Claude Haiku 4.5 (Bedrock)",
                      "api": "bedrock-converse-stream",
                      "reasoning": false,
                      "input": ["text", "image"],
                      "cost": {
                        "input": 1,
                        "output": 5,
                        "cacheRead": 0.1,
                        "cacheWrite": 1.25
                      },
                      "contextWindow": 200000,
                      "maxTokens": 4096
                    }
                  ]
                }
              },
              "bedrockDiscovery": {
                "enabled": false,
                "region": "ap-southeast-2",
                "providerFilter": ["anthropic", "amazon"],
                "refreshInterval": 3600,
                "defaultContextWindow": 32000,
                "defaultMaxTokens": 4096
              }
            },
            "plugins": {
              "load": {
                "paths": [
                  "/home/node/.openclaw/plugins/ms-graph-query"
                ]
              },
              "entries": {
                "ms-graph-query": {
                  "enabled": true,
                  "config": {
                    "tenantId": "${MSGRAPH_TENANT_ID:-}",
                    "clientId": "${MSGRAPH_CLIENT_ID:-}",
                    "delegatedScope": "offline_access openid profile User.Read Mail.ReadWrite Mail.Send Calendars.ReadWrite Files.ReadWrite Sites.ReadWrite.All",
                    "graphBaseUrl": "https://graph.microsoft.com",
                    "tokenStorePath": "~/.openclaw/ms-graph-query-tokens.json",
                    "allowedPathPrefixes": [
                      "/v1.0/sites",
                      "/v1.0/drives",
                      "/v1.0/me",
                      "/v1.0/users",
                      "/v1.0/search/query"
                    ],
                    "allowedUserEmails": [],
                    "largeFileThreshold": 4194304
                  }
                }
              }
            }
          }
    ms-graph-plugin:
      data:
        openclaw.plugin.json: |
$(sed 's/^/          /' plugins/ms-graph-query/openclaw.plugin.json)
        index.js: |
$(sed 's/^/          /' plugins/ms-graph-query/index.js)
    startup-script:
      data:
        start-openclaw.sh: |
          #!/bin/sh
          set -eu

          BOOTSTRAP_FILE="/home/node/.openclaw/workspace/BOOTSTRAP.md"
          BOOTSTRAP_MARKER="## Microsoft Graph Login"

          mkdir -p /home/node/.openclaw/workspace
          mkdir -p /home/node/.openclaw/plugins/ms-graph-query
          cp /plugin-source-ms-graph/openclaw.plugin.json /home/node/.openclaw/plugins/ms-graph-query/openclaw.plugin.json
          cp /plugin-source-ms-graph/index.js /home/node/.openclaw/plugins/ms-graph-query/index.js
          if [ ! -f "\$BOOTSTRAP_FILE" ]; then
            touch "\$BOOTSTRAP_FILE"
          fi

          if ! grep -qF "\$BOOTSTRAP_MARKER" "\$BOOTSTRAP_FILE"; then
            cat >> "\$BOOTSTRAP_FILE" <<'BOOTSTRAP_EOF'

          ## Microsoft Graph Login

          This pod includes the \`ms_graph_query\` plugin for Microsoft Graph access.

          Before using Microsoft Graph features, complete delegated device login:

          1. Run \`ms_graph_query\` with \`action="login_start"\`.
          2. Open the returned verification URL and enter the provided user code.
          3. Run \`ms_graph_query\` with \`action="login_poll"\` until authentication succeeds.
          4. Optionally run \`ms_graph_query\` with \`action="login_status"\` to confirm the token is stored.

          After login succeeds, the plugin can be used for Outlook, OneDrive, and SharePoint operations permitted by the configured Graph scopes.
          BOOTSTRAP_EOF
          fi

          exec openclaw gateway --bind lan --port 18789

  # Use the Talos hostpath storage class
  persistence:
    data:
      enabled: true
      type: persistentVolumeClaim
      accessMode: ReadWriteOnce
      size: 5Gi
      storageClass: talos-hostpath
    ms-graph-plugin:
      enabled: true
      type: configMap
      name: '{{ .Release.Name }}-ms-graph-plugin'
      globalMounts:
        - path: /plugin-source-ms-graph
          readOnly: true
    startup-script:
      enabled: true
      type: configMap
      name: '{{ .Release.Name }}-startup-script'
      globalMounts:
        - path: /scripts
          readOnly: true
EOF
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

    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
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

# Get gateway token
get_gateway_token() {
    log_info "Retrieving gateway token..."

    export KUBECONFIG="$KUBECONFIG_PATH"

    # Wait for pod to be ready
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s || true

    sleep 5

    GATEWAY_TOKEN=$(kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -o '"token": "[^"]*"' | cut -d'"' -f4)

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
    get_bedrock_credentials
    get_msgraph_config
    setup_helm_repo
    create_namespace
    create_secret
    create_values
    deploy_openclaw
    get_gateway_token
    show_access_info
}

# Run main function
main
