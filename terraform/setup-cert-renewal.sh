#!/bin/bash
#
# Setup Automatic Certificate Renewal
# Creates CronJob in Kubernetes to sync Let's Encrypt cert to ACM
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
AWS_REGION="ap-southeast-2"
AWS_PROFILE="personal"
NAMESPACE="openclaw"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}==>${NC} ${CYAN}$1${NC}\n"
}

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   Setup Certificate Auto-Renewal             ║"
    echo "║   Sync cert-manager certs to ACM daily       ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

# Create AWS credentials secret for CronJob
create_aws_credentials() {
    log_step "Creating AWS Credentials Secret"

    export KUBECONFIG="$KUBECONFIG_PATH"

    echo ""
    echo "The CronJob needs AWS credentials to upload certificates to ACM."
    echo ""
    echo "Option 1: Use IAM Role for Service Accounts (IRSA) - Recommended"
    echo "Option 2: Use AWS access keys - Simpler but less secure"
    echo ""
    read -p "Use access keys? (y/N): " use_keys

    if [[ $use_keys =~ ^[Yy]$ ]]; then
        echo ""
        echo -n "Enter AWS Access Key ID: "
        read -r AWS_ACCESS_KEY_ID

        echo -n "Enter AWS Secret Access Key: "
        read -rs AWS_SECRET_ACCESS_KEY
        echo ""

        kubectl create secret generic aws-credentials \
            --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
            --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
            --from-literal=AWS_DEFAULT_REGION="$AWS_REGION" \
            -n "$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -

        log_info "✓ AWS credentials secret created"
    else
        log_info "Using IRSA (configure IAM role separately)"
        log_info "See: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html"
    fi
}

# Create cert-sync CronJob
create_cronjob() {
    log_step "Creating Certificate Sync CronJob"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Creating CronJob to sync cert every day at 3 AM..."

    cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: openclaw-cert-sync-acm
  namespace: openclaw
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM UTC
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: openclaw-cert-sync
          containers:
          - name: cert-sync
            image: amazon/aws-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              set -e

              echo "Starting certificate sync to ACM..."

              # Extract certificate components
              CERT=$(cat /certs/tls.crt | base64 -w0)
              KEY=$(cat /certs/tls.key | base64 -w0)
              CA=$(cat /certs/ca.crt | base64 -w0) || CA=""

              # Get domain from certificate
              DOMAIN=$(openssl x509 -in /certs/tls.crt -noout -subject | sed 's/.*CN = //')
              echo "Domain: $DOMAIN"

              # Check if cert already exists in ACM
              EXISTING_ARN=$(aws acm list-certificates \
                --region ${AWS_REGION} \
                --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
                --output text)

              # Prepare import command
              if [ -n "$CA" ]; then
                IMPORT_CMD="aws acm import-certificate \
                  --region ${AWS_REGION} \
                  --certificate file:///certs/tls.crt \
                  --private-key file:///certs/tls.key \
                  --certificate-chain file:///certs/ca.crt"
              else
                IMPORT_CMD="aws acm import-certificate \
                  --region ${AWS_REGION} \
                  --certificate file:///certs/tls.crt \
                  --private-key file:///certs/tls.key"
              fi

              if [ -n "$EXISTING_ARN" ]; then
                echo "Updating existing certificate: $EXISTING_ARN"
                $IMPORT_CMD --certificate-arn "$EXISTING_ARN"
              else
                echo "Importing new certificate"
                $IMPORT_CMD --tags Key=Name,Value=openclaw-letsencrypt Key=Source,Value=cert-manager
              fi

              echo "✓ Certificate synced to ACM successfully"
            env:
            - name: AWS_REGION
              value: "ap-southeast-2"
            envFrom:
            - secretRef:
                name: aws-credentials
            volumeMounts:
            - name: certs
              mountPath: /certs
              readOnly: true
          volumes:
          - name: certs
            secret:
              secretName: openclaw-tls-secret
EOF

    log_info "✓ CronJob created: openclaw-cert-sync-acm"
}

# Create ServiceAccount and RBAC
create_rbac() {
    log_step "Creating ServiceAccount and RBAC"

    export KUBECONFIG="$KUBECONFIG_PATH"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openclaw-cert-sync
  namespace: openclaw
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: openclaw-cert-reader
  namespace: openclaw
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["openclaw-tls-secret"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: openclaw-cert-sync-binding
  namespace: openclaw
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: openclaw-cert-reader
subjects:
- kind: ServiceAccount
  name: openclaw-cert-sync
  namespace: openclaw
EOF

    log_info "✓ RBAC configured"
}

# Test manual sync
test_sync() {
    log_step "Testing Manual Certificate Sync"

    export KUBECONFIG="$KUBECONFIG_PATH"

    log_info "Creating test job..."

    kubectl create job openclaw-cert-sync-test \
        --from=cronjob/openclaw-cert-sync-acm \
        -n "$NAMESPACE"

    log_info "Waiting for job to complete..."
    kubectl wait --for=condition=complete job/openclaw-cert-sync-test \
        -n "$NAMESPACE" \
        --timeout=120s || true

    echo ""
    echo "Job logs:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl logs job/openclaw-cert-sync-test -n "$NAMESPACE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo ""
    read -p "Delete test job? (Y/n): " delete_job
    if [[ ! $delete_job =~ ^[Nn]$ ]]; then
        kubectl delete job openclaw-cert-sync-test -n "$NAMESPACE"
        log_info "✓ Test job deleted"
    fi
}

# Show completion
show_completion() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "✅ Certificate Auto-Renewal Configured"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "CronJob Schedule: Daily at 3 AM UTC"
    echo "Namespace: openclaw"
    echo "CronJob Name: openclaw-cert-sync-acm"
    echo ""
    echo "Monitor renewal jobs:"
    echo "  kubectl get cronjobs -n openclaw"
    echo "  kubectl get jobs -n openclaw"
    echo "  kubectl logs -l job-name=openclaw-cert-sync-acm -n openclaw"
    echo ""
    echo "Manual sync:"
    echo "  kubectl create job manual-sync --from=cronjob/openclaw-cert-sync-acm -n openclaw"
    echo ""
    echo "Certificate expiry:"
    echo "  kubectl get certificate openclaw-tls -n openclaw"
    echo ""
}

# Main execution
main() {
    show_banner
    check_certificate
    create_rbac
    create_aws_credentials
    create_cronjob

    echo ""
    read -p "Run a test sync now? (Y/n): " run_test
    if [[ ! $run_test =~ ^[Nn]$ ]]; then
        test_sync
    fi

    show_completion
}

# Run main function
main
