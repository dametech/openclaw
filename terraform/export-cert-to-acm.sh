#!/bin/bash
#
# Export Let's Encrypt Certificate from Kubernetes to AWS ACM
# Extracts cert from cert-manager secret and uploads to ACM
#

set -e

# Configuration
KUBECONFIG_PATH="${HOME}/.kube/au01-0.yaml"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
AWS_PROFILE="${AWS_PROFILE:-personal}"
NAMESPACE="openclaw"
SECRET_NAME="openclaw-tls-secret"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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
    echo -e "\n${BLUE}==>${NC} $1\n"
}

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   Export Let's Encrypt Cert to ACM           ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

# Check certificate is ready
check_certificate() {
    log_step "Checking certificate status"

    export KUBECONFIG="$KUBECONFIG_PATH"

    if ! kubectl get certificate openclaw-tls -n "$NAMESPACE" &>/dev/null; then
        log_error "Certificate 'openclaw-tls' not found in namespace $NAMESPACE"
        echo "Run ./cert-manager-setup.sh first"
        exit 1
    fi

    local ready=$(kubectl get certificate openclaw-tls -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    if [ "$ready" != "True" ]; then
        log_error "Certificate is not ready yet"
        echo ""
        kubectl describe certificate openclaw-tls -n "$NAMESPACE"
        exit 1
    fi

    log_info "✓ Certificate is ready"
}

# Export certificate from Kubernetes
export_certificate() {
    log_step "Exporting certificate from Kubernetes"

    export KUBECONFIG="$KUBECONFIG_PATH"

    # Create temp directory
    CERT_DIR=$(mktemp -d)
    log_info "Using temp directory: $CERT_DIR"

    # Extract certificate
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT_DIR/certificate.pem"

    # Extract private key
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.data.tls\.key}' | base64 -d > "$CERT_DIR/private-key.pem"

    # Extract CA chain
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.data.ca\.crt}' | base64 -d > "$CERT_DIR/ca-chain.pem" 2>/dev/null || \
        log_warn "No CA chain found in secret (might not be needed)"

    log_info "✓ Certificate exported"
    echo "  - Certificate: $CERT_DIR/certificate.pem"
    echo "  - Private Key: $CERT_DIR/private-key.pem"
    if [ -f "$CERT_DIR/ca-chain.pem" ]; then
        echo "  - CA Chain: $CERT_DIR/ca-chain.pem"
    fi

    echo "$CERT_DIR"
}

# Upload to ACM
upload_to_acm() {
    log_step "Uploading certificate to AWS ACM"

    local cert_dir="$1"

    # Check if certificate already exists
    DOMAIN=$(openssl x509 -in "$cert_dir/certificate.pem" -noout -subject | sed 's/.*CN = //')
    log_info "Certificate domain: $DOMAIN"

    # Check for existing cert
    EXISTING_ARN=$(aws acm list-certificates \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
        --output text 2>/dev/null)

    if [ -n "$EXISTING_ARN" ]; then
        log_warn "Certificate already exists in ACM: $EXISTING_ARN"
        read -p "Delete and re-import? (y/N): " delete_existing

        if [[ $delete_existing =~ ^[Yy]$ ]]; then
            log_info "Deleting existing certificate..."
            aws acm delete-certificate \
                --profile "$AWS_PROFILE" \
                --region "$AWS_REGION" \
                --certificate-arn "$EXISTING_ARN"
            sleep 5
        else
            log_info "Using existing certificate ARN"
            echo "$EXISTING_ARN"
            return
        fi
    fi

    # Import certificate to ACM
    log_info "Importing certificate to ACM..."

    if [ -f "$cert_dir/ca-chain.pem" ] && [ -s "$cert_dir/ca-chain.pem" ]; then
        CERT_ARN=$(aws acm import-certificate \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --certificate fileb://"$cert_dir/certificate.pem" \
            --private-key fileb://"$cert_dir/private-key.pem" \
            --certificate-chain fileb://"$cert_dir/ca-chain.pem" \
            --tags "Key=Name,Value=openclaw-letsencrypt" "Key=Source,Value=cert-manager" "Key=Domain,Value=$DOMAIN" \
            --query 'CertificateArn' \
            --output text)
    else
        CERT_ARN=$(aws acm import-certificate \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --certificate fileb://"$cert_dir/certificate.pem" \
            --private-key fileb://"$cert_dir/private-key.pem" \
            --tags "Key=Name,Value=openclaw-letsencrypt" "Key=Source,Value=cert-manager" "Key=Domain,Value=$DOMAIN" \
            --query 'CertificateArn' \
            --output text)
    fi

    log_info "✓ Certificate imported to ACM"
    echo ""
    echo "  ARN: $CERT_ARN"
    echo "  Domain: $DOMAIN"
    echo ""

    # Save ARN to file for Terraform
    echo "$CERT_ARN" > /tmp/openclaw-acm-cert-arn.txt
    log_info "ARN saved to: /tmp/openclaw-acm-cert-arn.txt"

    echo "$CERT_ARN"
}

# Main execution
main() {
    show_banner

    check_certificate
    CERT_DIR=$(export_certificate)
    CERT_ARN=$(upload_to_acm "$CERT_DIR")

    # Cleanup temp directory
    rm -rf "$CERT_DIR"

    echo ""
    log_info "✅ Certificate exported and uploaded to ACM"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Next steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Add this to terraform.tfvars:"
    echo ""
    echo "   acm_certificate_arn = \"$CERT_ARN\""
    echo ""
    echo "2. Deploy Terraform infrastructure:"
    echo "   cd terraform"
    echo "   terraform init"
    echo "   terraform apply"
    echo ""
    echo "3. Set up auto-renewal (certificates expire in 90 days):"
    echo "   ./terraform/setup-cert-renewal.sh"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Run main function
main
