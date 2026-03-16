#!/bin/bash
#
# OpenClaw Slack Integration Testing Script
# Comprehensive testing and verification
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
NAMESPACE="openclaw"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "\n${BLUE}==>${NC} ${CYAN}$1${NC}\n"
}

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   OpenClaw Slack Integration Testing         ║"
    echo "║   Verify and Troubleshoot Your Setup         ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

# Test 1: Check pod is running
test_pod_status() {
    log_step "Test 1: Pod Status"

    export KUBECONFIG="$KUBECONFIG_PATH"

    local pod_status=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].status.phase}' 2>/dev/null)

    if [ "$pod_status" = "Running" ]; then
        log_info "✓ Pod is running"

        local ready=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="main")].ready}' 2>/dev/null)

        if [ "$ready" = "true" ]; then
            log_info "✓ Main container is ready"
            return 0
        else
            log_warn "⚠ Main container is not ready"
            return 1
        fi
    else
        log_error "✗ Pod is not running (status: $pod_status)"
        return 1
    fi
}

# Test 2: Check secrets exist
test_secrets() {
    log_step "Test 2: Kubernetes Secrets"

    export KUBECONFIG="$KUBECONFIG_PATH"

    if kubectl get secret openclaw-slack-tokens -n "$NAMESPACE" &>/dev/null; then
        log_info "✓ Slack tokens secret exists"

        # Check if tokens are set
        local app_token=$(kubectl get secret openclaw-slack-tokens -n "$NAMESPACE" -o jsonpath='{.data.SLACK_APP_TOKEN}' | base64 -d 2>/dev/null | head -c 10)
        local bot_token=$(kubectl get secret openclaw-slack-tokens -n "$NAMESPACE" -o jsonpath='{.data.SLACK_BOT_TOKEN}' | base64 -d 2>/dev/null | head -c 10)

        if [[ $app_token =~ ^xapp- ]]; then
            log_info "✓ App token is set correctly (${app_token}...)"
        else
            log_error "✗ App token format is invalid"
            return 1
        fi

        if [[ $bot_token =~ ^xoxb- ]]; then
            log_info "✓ Bot token is set correctly (${bot_token}...)"
        else
            log_error "✗ Bot token format is invalid"
            return 1
        fi

        return 0
    else
        log_error "✗ Slack tokens secret not found"
        echo "  Run: ./setup-slack-integration.sh"
        return 1
    fi
}

# Test 3: Check configuration
test_config() {
    log_step "Test 3: OpenClaw Configuration"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Checking openclaw.json for Slack configuration..."

    local config=$(kubectl get configmap openclaw -n "$NAMESPACE" -o jsonpath='{.data.openclaw\.json}' 2>/dev/null)

    if echo "$config" | grep -q '"slack"'; then
        log_info "✓ Slack channel configuration found"

        if echo "$config" | grep -q '"enabled": true'; then
            log_info "✓ Slack channel is enabled"
        else
            log_warn "⚠ Slack channel is disabled"
            return 1
        fi

        if echo "$config" | grep -q '"mode": "socket"'; then
            log_info "✓ Socket Mode is configured"
        else
            log_warn "⚠ Socket Mode is not configured"
        fi

        return 0
    else
        log_error "✗ Slack configuration not found in openclaw.json"
        return 1
    fi
}

# Test 4: Check logs for Slack connection
test_slack_connection() {
    log_step "Test 4: Slack Connection Status"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Checking logs for Slack connection..."

    local logs=$(kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -c main --tail=100 2>/dev/null)

    if echo "$logs" | grep -qi "slack.*connected\|socket.*connected\|slack.*ready"; then
        log_info "✓ Slack connection established"
        echo "$logs" | grep -i "slack\|socket" | tail -5
        return 0
    elif echo "$logs" | grep -qi "slack.*error\|slack.*failed\|invalid.*token"; then
        log_error "✗ Slack connection failed"
        echo ""
        echo "Recent errors:"
        echo "$logs" | grep -i "error\|failed" | tail -5
        return 1
    else
        log_warn "⚠ No clear connection status in logs"
        echo ""
        echo "Recent Slack-related logs:"
        echo "$logs" | grep -i "slack\|socket\|channel" | tail -10
        return 1
    fi
}

# Test 5: Check pairing status
test_pairing() {
    log_step "Test 5: Pairing Status"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Checking for pending pairing requests..."

    local pairing_output=$(kubectl exec -n "$NAMESPACE" deployment/openclaw -c main -- \
        node dist/index.js pairing list 2>/dev/null || echo "COMMAND_FAILED")

    if [ "$pairing_output" = "COMMAND_FAILED" ]; then
        log_warn "⚠ Could not check pairing status (command may not be available)"
        return 1
    fi

    if echo "$pairing_output" | grep -qi "pending\|waiting"; then
        log_warn "⚠ Pending pairing requests found"
        echo "$pairing_output"
        echo ""
        echo "To approve a pairing request:"
        echo "  kubectl exec -n $NAMESPACE deployment/openclaw -c main -- \\"
        echo "    node dist/index.js pairing approve slack <code>"
        return 1
    else
        log_info "✓ No pending pairing requests"
        return 0
    fi
}

# Test 6: Environment variables check
test_env_vars() {
    log_step "Test 6: Environment Variables"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Checking if Slack tokens are available in container..."

    local env_check=$(kubectl exec -n "$NAMESPACE" deployment/openclaw -c main -- \
        sh -c 'echo "APP_TOKEN: ${SLACK_APP_TOKEN:0:10}... BOT_TOKEN: ${SLACK_BOT_TOKEN:0:10}..."' 2>/dev/null)

    if [[ $env_check =~ xapp- ]] && [[ $env_check =~ xoxb- ]]; then
        log_info "✓ Environment variables are set"
        echo "  $env_check"
        return 0
    else
        log_error "✗ Environment variables are not set correctly"
        echo "  $env_check"
        return 1
    fi
}

# Show test summary
show_summary() {
    log_step "Test Summary"

    local total_tests=6
    local passed=0

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if test_pod_status; then ((passed++)); fi
    echo ""
    if test_secrets; then ((passed++)); fi
    echo ""
    if test_config; then ((passed++)); fi
    echo ""
    if test_slack_connection; then ((passed++)); fi
    echo ""
    if test_pairing; then ((passed++)); fi
    echo ""
    if test_env_vars; then ((passed++)); fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ $passed -eq $total_tests ]; then
        log_info "✅ All tests passed ($passed/$total_tests)"
        echo ""
        echo "Your Slack integration is ready to use!"
        return 0
    elif [ $passed -ge 4 ]; then
        log_warn "⚠️  Most tests passed ($passed/$total_tests)"
        echo ""
        echo "Integration is mostly working but has some issues."
        return 1
    else
        log_error "❌ Multiple tests failed ($passed/$total_tests)"
        echo ""
        echo "Integration needs attention. See errors above."
        return 1
    fi
}

# Interactive test menu
show_manual_test_instructions() {
    log_step "Manual Testing Instructions"

    cat <<'EOF'

Now test the integration manually in Slack:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📱 TEST 1: Send a Direct Message
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. Open Slack
   2. Go to "Apps" section in sidebar
   3. Find "OpenClaw Bot"
   4. Send a message: "Hello!"
   5. You should get a response

   If pairing is required:
   - Bot will respond with a pairing code
   - Run: kubectl exec -n openclaw deployment/openclaw -c main -- \
           node dist/index.js pairing approve slack <code>
   - Try sending another message

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💬 TEST 2: Invite to Channel
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. Go to any Slack channel
   2. Type: /invite @OpenClaw
   3. Mention the bot: @OpenClaw what can you help with?
   4. Bot should respond to the mention

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔍 TEST 3: Check Logs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Watch logs in real-time:

   kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main -f

   Look for:
   - [slack] Received message
   - [slack] Sending response
   - Any error messages

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# Troubleshooting helper
show_troubleshooting() {
    log_step "Troubleshooting Guide"

    cat <<'EOF'

Common Issues and Solutions:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ ISSUE: Bot not responding to messages
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Possible causes:

   1. Pairing required
      → Check logs for pairing code
      → Approve with: kubectl exec ... pairing approve slack <code>

   2. Invalid tokens
      → Verify tokens in Kubernetes secret
      → Regenerate tokens in Slack app settings

   3. Socket Mode connection failed
      → Check logs for connection errors
      → Verify Socket Mode is enabled in Slack app
      → Restart pod: kubectl rollout restart deployment/openclaw -n openclaw

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ ISSUE: "Socket connection failed" in logs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Solutions:

   1. Check App Token
      → Must start with xapp-
      → Verify in Slack app settings → Socket Mode
      → Regenerate if needed

   2. Check network connectivity
      → Pod must have outbound internet access
      → Verify firewall rules allow WebSocket connections

   3. Restart pod
      → kubectl rollout restart deployment/openclaw -n openclaw

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ ISSUE: "Invalid token" errors
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Solutions:

   1. Regenerate tokens
      → Go to https://api.slack.com/apps
      → Socket Mode: Regenerate app token
      → OAuth & Permissions: Reinstall to workspace for bot token

   2. Update secrets
      → kubectl delete secret openclaw-slack-tokens -n openclaw
      → Run ./setup-slack-integration.sh again

   3. Restart pod
      → kubectl rollout restart deployment/openclaw -n openclaw

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# Get detailed logs
get_detailed_logs() {
    log_step "Detailed Logs"

    export KUBECONFIG="$KUBECONFIG_PATH"

    echo "Last 50 log lines:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -c main --tail=50
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main menu
show_menu() {
    cat <<'EOF'

Choose an option:

  1) Run all automated tests
  2) Show manual testing instructions
  3) Show troubleshooting guide
  4) View detailed logs
  5) Exit

EOF

    read -p "Enter choice (1-5): " choice

    case $choice in
        1)
            show_summary
            show_manual_test_instructions
            ;;
        2)
            show_manual_test_instructions
            ;;
        3)
            show_troubleshooting
            ;;
        4)
            get_detailed_logs
            ;;
        5)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    show_banner
    show_menu
}

# Run main function
main
