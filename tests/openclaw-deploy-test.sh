#!/bin/bash

set -euo pipefail

SCRIPT="openclaw-deploy.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'echo -n "Enter instance name [$RELEASE_NAME]: "'
assert_contains 'echo -n "Use an existing PVC for data? [y/N]: "'
assert_contains 'echo -n "Enter existing PVC name: "'
assert_contains 'Existing PVC name cannot be empty when enabled.'
assert_contains 'delete_existing_release_pvcs()'
assert_contains 'kubectl get pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o name'
assert_contains 'Existing PersistentVolumeClaim(s) found for release'
assert_contains 'These PVCs will be deleted before deployment continues.'
assert_contains 'echo -n "Delete these PVCs and continue? [Y/n]: "'
assert_contains 'Deployment cancelled because existing PVCs were not approved for deletion.'
assert_contains 'helm_release_exists()'
assert_contains 'helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1'
assert_contains 'helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"'
assert_contains 'kubectl wait --for=delete pod -l "app.kubernetes.io/instance=$RELEASE_NAME" -n "$NAMESPACE" --timeout=180s || true'
assert_contains 'delete_release_configmaps()'
assert_contains 'kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-config" --ignore-not-found'
assert_contains 'kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-scripts" --ignore-not-found'
assert_contains 'kubectl delete configmap -n "$NAMESPACE" "${RELEASE_NAME}-startup-script" --ignore-not-found'
assert_contains 'validate_generated_config()'
assert_contains 'OPENCLAW_CONFIG_TEMPLATE="openclaw/openclaw.json"'
assert_contains 'GATEWAY_AUTH_TOKEN=""'
assert_contains 'render_openclaw_config()'
assert_contains 'json.loads(Path(rendered_config_path).read_text())'
assert_contains 'python3 - <<PY'
assert_contains 'template_path = Path('
assert_contains 'rendered_config_path = Path('
assert_contains 'template = template_path.read_text()'
assert_contains 'rendered = template'
assert_contains '__GATEWAY_AUTH_TOKEN_JSON__'
assert_contains 'CONFIG_MODE: replace'
assert_contains 'kubectl delete -n "$NAMESPACE" $pvc_names'
assert_contains 'kubectl wait --for=delete "$pvc_name" -n "$NAMESPACE" --timeout=180s || true'
assert_contains 'EXISTING_PVC=""'
assert_contains '--release-name NAME'
assert_contains '--existing-pvc NAME'
assert_contains 'RELEASE_NAME="$2"'
assert_contains 'EXISTING_PVC="$2"'
assert_contains 'if [ -n "$RELEASE_NAME" ] && [ "$RELEASE_NAME" != "openclaw" ]; then'
assert_contains 'Using instance name from arguments: $RELEASE_NAME'
assert_contains 'if [ -n "$EXISTING_PVC" ]; then'
assert_contains 'RELEASE_NAME="$EXISTING_PVC"'
assert_contains 'if [ -n "$EXISTING_PVC" ]; then'
assert_contains 'Using existing PVC for data persistence: $EXISTING_PVC'
assert_contains 'data:'
assert_contains 'enabled: false'
assert_contains 'restored-data:'
assert_contains 'existingClaim: $EXISTING_PVC'
assert_contains 'globalMounts:'
assert_contains '- path: /home/node/.openclaw'
assert_contains 'Defaulting release name to existing PVC name: $RELEASE_NAME'
assert_contains 'SECRET_NAME="${RELEASE_NAME}-env-secret"'
assert_contains 'VALUES_FILE="/tmp/${RELEASE_NAME}-values.yaml"'
assert_contains 'fullnameOverride: $RELEASE_NAME'
assert_contains 'echo -n "Enter your AWS Access Key ID: "'
assert_contains 'echo -n "Enter your AWS Secret Access Key: "'
assert_contains 'AWS_ACCESS_KEY_ID'
assert_contains 'AWS_SECRET_ACCESS_KEY'
assert_contains 'AWS_SESSION_TOKEN'
assert_contains 'Using AWS_ACCESS_KEY_ID from environment'
assert_contains 'AWS_ACCESS_KEY_ID is required'
assert_contains 'AWS_SECRET_ACCESS_KEY is required'
assert_contains 'name: $SECRET_NAME'
assert_contains 'name: $SECRET_NAME'
assert_contains 'helm upgrade "$RELEASE_NAME" "$HELM_REPO/openclaw" \'
assert_contains '--values "$VALUES_FILE" \'
assert_contains '/home/node/.openclaw/plugins/pod-delegate'
assert_contains 'pod-delegate-plugin:'
assert_contains 'name: '\''{{ .Release.Name }}-pod-delegate-plugin'\'''
assert_contains 'mkdir -p /home/node/.openclaw/plugins/pod-delegate'
assert_contains 'cp /plugin-source-ms-graph/package.json /home/node/.openclaw/plugins/ms-graph-query/package.json'
assert_contains 'cp /plugin-source-jira/package.json /home/node/.openclaw/plugins/jira-query/package.json'
assert_contains 'cp /plugin-source-pod-delegate/package.json /home/node/.openclaw/plugins/pod-delegate/package.json'
assert_contains 'cp /plugin-source-pod-delegate/openclaw.plugin.json /home/node/.openclaw/plugins/pod-delegate/openclaw.plugin.json'
assert_contains 'cp /plugin-source-pod-delegate/index.js /home/node/.openclaw/plugins/pod-delegate/index.js'
assert_contains 'bootstrap-doc:'
assert_contains 'BOOTSTRAP.md: |'
assert_contains '$(sed '\''s/^/          /'\'' "$RENDERED_CONFIG_JSON")'
assert_contains 'openclaw/plugins/ms-graph-query/package.json'
assert_contains 'openclaw/plugins/jira-query/package.json'
assert_contains 'openclaw/plugins/pod-delegate/package.json'
assert_contains 'openclaw/openclaw.json'
assert_contains 'openclaw/workspace/BOOTSTRAP.md'
assert_contains 'BOOTSTRAP_SOURCE="/bootstrap-source/BOOTSTRAP.md"'
assert_contains 'BOOTSTRAP_VERSION_FILE="/home/node/.openclaw/workspace/.bootstrap-version"'
assert_contains 'DEPLOYED_BOOTSTRAP_HASH="$(cat "\$BOOTSTRAP_VERSION_FILE" 2>/dev/null || true)"'
assert_contains 'BOOTSTRAP_SOURCE_HASH="$(sha256sum "\$BOOTSTRAP_SOURCE" | awk '\''{print $1}'\'')"'
assert_contains 'if [ ! -f "\$BOOTSTRAP_FILE" ] || [ "\$BOOTSTRAP_SOURCE_HASH" != "\$DEPLOYED_BOOTSTRAP_HASH" ]; then'
assert_contains 'cp "\$BOOTSTRAP_SOURCE" "\$BOOTSTRAP_FILE"'
assert_contains 'printf '\''%s\n'\'' "\$BOOTSTRAP_SOURCE_HASH" > "\$BOOTSTRAP_VERSION_FILE"'
assert_contains 'exec openclaw gateway --bind lan --port 18789'
assert_contains 'openclaw.json: |'
assert_contains '18789'
assert_contains 'deployment/$RELEASE_NAME'
assert_contains 'svc/$RELEASE_NAME'
assert_contains 'show_deploy_diagnostics()'
assert_contains 'check_cluster_disk_pressure()'
assert_contains 'Checking cluster for disk pressure...'
assert_contains 'kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints --no-headers'
assert_contains 'node.kubernetes.io/disk-pressure'
assert_contains 'Cluster has node(s) under disk pressure:'
assert_contains 'helm status "$RELEASE_NAME" -n "$NAMESPACE" || true'
assert_contains 'kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o wide || true'
assert_contains 'kubectl describe deployment "$RELEASE_NAME" -n "$NAMESPACE" || true'
assert_contains 'kubectl describe pod -n "$NAMESPACE" "$pod_name" || true'
assert_contains 'Helm deployment did not become ready. Gathering diagnostics...'
assert_contains 'if ! helm'
assert_contains 'ensure_gateway_auth_token()'
assert_contains 'Preserving existing gateway token or generating a new one...'
assert_contains 'current_token=$(kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | python3 -c '
assert_contains 'python3 -c '
assert_contains 'print(json.loads(data).get("gateway", {}).get("auth", {}).get("token", "") if data else "")'
assert_contains 'if [ -n "$current_token" ]; then'
assert_contains 'GATEWAY_AUTH_TOKEN="$current_token"'
assert_contains 'GATEWAY_AUTH_TOKEN=$(python3 - <<'\''PY'\'''
assert_contains 'import secrets'
assert_contains 'print(secrets.token_urlsafe(32))'
assert_contains 'apply_rendered_openclaw_config()'
assert_contains 'Overwriting /home/node/.openclaw/openclaw.json in pod with rendered config...'
assert_contains 'current_hash=$(kubectl exec -n "$NAMESPACE" "$pod_name" -c main -- sh -c '
assert_contains 'sha256sum /home/node/.openclaw/openclaw.json 2>/dev/null | awk'
assert_contains 'rendered_hash=$(sha256sum "$RENDERED_CONFIG_JSON" | awk '\''{print $1}'\'')'
assert_contains 'if [ -n "$current_hash" ] && [ "$current_hash" = "$rendered_hash" ]; then'
assert_contains 'Rendered openclaw.json already matches pod config. Skipping overwrite.'
assert_contains 'pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='\''{.items[0].metadata.name}'\'')'
assert_contains 'kubectl cp "$RENDERED_CONFIG_JSON" "$NAMESPACE/$pod_name:/home/node/.openclaw/openclaw.json" -c main'
assert_contains 'GATEWAY_TOKEN=$(kubectl exec -n "$NAMESPACE" "deployment/$RELEASE_NAME" -c main -- cat /home/node/.openclaw/openclaw.json 2>/dev/null | python3 -c '
assert_contains 'AWS_ACCESS_KEY_ID:'
assert_contains 'AWS_SECRET_ACCESS_KEY:'
assert_contains 'AWS_REGION: "ap-southeast-2"'
assert_contains 'kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found'
assert_contains 'name: '\''{{ .Release.Name }}-bootstrap-doc'\'''
assert_contains '- path: /bootstrap-source'
if grep -Fq -- '- loopback' "$SCRIPT"; then
    echo "unexpected loopback bind mode in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'POST_RENDERER_FILE=' "$SCRIPT" || grep -Fq -- '--post-renderer' "$SCRIPT"; then
    echo "unexpected post-renderer logic in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'yaml.safe_load_all' "$SCRIPT"; then
    echo "unexpected embedded yaml post-renderer in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'ANTHROPIC_API_KEY' "$SCRIPT"; then
    echo "unexpected Anthropic API key handling in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'anthropic/claude-opus-4-6' "$SCRIPT"; then
    echo "unexpected Anthropic model handling in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- '"id": "opus"' "$SCRIPT" || grep -Fq -- '"id": "haiku"' "$SCRIPT"; then
    echo "unexpected separate model agents in $SCRIPT" >&2
    exit 1
fi

echo "openclaw-deploy.sh checks passed"
