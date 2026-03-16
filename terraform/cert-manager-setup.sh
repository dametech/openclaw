#!/bin/bash
#
# Install and configure cert-manager for Let's Encrypt certificates
# Generates certificates in Kubernetes and syncs to AWS ACM for ALB
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
CERT_MANAGER_VERSION="v1.16.2"
AWS_REGION="ap-southeast-2"
AWS_PROFILE="personal"

# Colors
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

log_step() {
    echo -e "\n${BLUE}==>${NC} ${CYAN}$1${NC}\n"
}

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   cert-manager Setup for Let's Encrypt       ║"
    echo "║   Kubernetes Certificate Management          ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

# Install cert-manager
install_cert_manager() {
    log_step "Step 1: Install cert-manager"

    export KUBECONFIG="$KUBECONFIG_PATH"

    # Check if already installed
    if kubectl get namespace cert-manager &>/dev/null; then
        log_warn "cert-manager namespace already exists"
        read -p "Reinstall cert-manager? (y/N): " reinstall
        if [[ ! $reinstall =~ ^[Yy]$ ]]; then
            log_info "Skipping cert-manager installation"
            return
        fi
    fi

    log_info "Installing cert-manager $CERT_MANAGER_VERSION..."

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml

    log_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=cert-manager \
        -n cert-manager \
        --timeout=300s

    kubectl wait --for=condition=ready pod \
        -l app=webhook \
        -n cert-manager \
        --timeout=300s

    log_info "✓ cert-manager installed successfully"
}

# Create Let's Encrypt ClusterIssuer
create_letsencrypt_issuer() {
    log_step "Step 2: Create Let's Encrypt Issuer"

    export KUBECONFIG="$KUBECONFIG_PATH"

    echo ""
    echo -n "Enter your email for Let's Encrypt notifications: "
    read -r EMAIL

    if [ -z "$EMAIL" ]; then
        log_warn "No email provided, using default"
        EMAIL="admin@example.com"
    fi

    log_info "Creating Let's Encrypt ClusterIssuers..."

    # Create staging issuer (for testing)
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

    # Create production issuer
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

    log_info "✓ ClusterIssuers created"
    echo "  - letsencrypt-staging (for testing)"
    echo "  - letsencrypt-prod (for production)"
}

# Create certificate for OpenClaw
create_certificate() {
    log_step "Step 3: Request Let's Encrypt Certificate"

    export KUBECONFIG="$KUBECONFIG_PATH"

    echo ""
    echo -n "Enter domain name for OpenClaw (e.g., openclaw.yourdomain.com): "
    read -r DOMAIN

    if [ -z "$DOMAIN" ]; then
        log_warn "No domain provided, skipping certificate creation"
        return
    fi

    echo ""
    echo "Choose issuer:"
    echo "  1) letsencrypt-staging (recommended for testing)"
    echo "  2) letsencrypt-prod (for production)"
    read -p "Enter choice (1 or 2): " issuer_choice

    case $issuer_choice in
        1)
            ISSUER="letsencrypt-staging"
            ;;
        2)
            ISSUER="letsencrypt-prod"
            log_warn "Production issuer has rate limits! Test with staging first."
            ;;
        *)
            log_warn "Invalid choice, using staging"
            ISSUER="letsencrypt-staging"
            ;;
    esac

    log_info "Creating Certificate resource..."

    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openclaw-tls
  namespace: openclaw
spec:
  secretName: openclaw-tls-secret
  issuerRef:
    name: $ISSUER
    kind: ClusterIssuer
  dnsNames:
    - $DOMAIN
  privateKey:
    algorithm: RSA
    size: 2048
  usages:
    - digital signature
    - key encipherment
EOF

    log_info "✓ Certificate resource created"
    echo ""
    echo "Checking certificate status..."
    sleep 5

    kubectl get certificate openclaw-tls -n openclaw

    echo ""
    log_info "To check certificate progress:"
    echo "  kubectl describe certificate openclaw-tls -n openclaw"
    echo "  kubectl get certificaterequest -n openclaw"
    echo ""
    log_info "Certificate will be saved to secret: openclaw-tls-secret"
}

# Show next steps
show_completion() {
    log_step "✅ cert-manager Setup Complete"

    cat <<'EOF'

Next Steps:

1. Wait for certificate to be issued:
   kubectl get certificate openclaw-tls -n openclaw
   # Status should show "Ready: True"

2. Export certificate for ACM upload:
   ./terraform/export-cert-to-acm.sh

3. Update terraform.tfvars with ACM certificate ARN

4. Deploy Terraform infrastructure:
   cd terraform
   terraform init
   terraform plan
   terraform apply

5. Configure Azure Bot messaging endpoint with ALB URL

Documentation:
- cert-manager: https://cert-manager.io/docs/
- Let's Encrypt: https://letsencrypt.org/docs/

EOF
}

# Main execution
main() {
    show_banner
    install_cert_manager
    create_letsencrypt_issuer
    create_certificate
    show_completion
}

# Run main function
main
