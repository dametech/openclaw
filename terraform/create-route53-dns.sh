#!/bin/bash
#
# Create Route53 DNS Record for OpenClaw
# Points domain to ALB for Teams webhook
#

set -e

# Configuration
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
AWS_PROFILE="${AWS_PROFILE:-personal}"
DOMAIN_NAME="${1:-openclaw.au01-0.dametech.net}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}==>${NC} $1\n"
}

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   Route53 DNS Setup for OpenClaw             ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

# Find Route53 hosted zone
find_hosted_zone() {
    log_step "Finding Route53 Hosted Zone"

    # Extract base domain from full domain
    # openclaw.au01-0.dametech.net → dametech.net
    BASE_DOMAIN=$(echo "$DOMAIN_NAME" | awk -F. '{print $(NF-1)"."$NF}')

    log_info "Looking for hosted zone: $BASE_DOMAIN"

    ZONE_ID=$(aws route53 list-hosted-zones \
        --profile "$AWS_PROFILE" \
        --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id" \
        --output text | cut -d'/' -f3)

    if [ -z "$ZONE_ID" ]; then
        log_warn "Hosted zone not found for $BASE_DOMAIN"
        echo ""
        echo "Available hosted zones:"
        aws route53 list-hosted-zones \
            --profile "$AWS_PROFILE" \
            --query 'HostedZones[].[Name,Id]' \
            --output table

        echo ""
        read -p "Enter hosted zone ID manually: " ZONE_ID
    fi

    if [ -z "$ZONE_ID" ]; then
        echo "Error: No zone ID provided"
        exit 1
    fi

    log_info "✓ Using hosted zone: $ZONE_ID ($BASE_DOMAIN)"
}

# Get ALB DNS name
get_alb_dns() {
    log_step "Getting ALB DNS Name"

    # Check if Terraform has been deployed
    if [ -f terraform.tfstate ]; then
        log_info "Reading from Terraform state..."
        ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
        ALB_ZONE_ID=$(terraform output -raw alb_zone_id 2>/dev/null)

        if [ -n "$ALB_DNS" ]; then
            log_info "✓ Found ALB from Terraform: $ALB_DNS"
            echo "$ALB_DNS"
            echo "$ALB_ZONE_ID"
            return
        fi
    fi

    # Search for ALB by name
    log_info "Searching for OpenClaw ALB..."

    local alb_info=$(aws elbv2 describe-load-balancers \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName, 'openclaw')][DNSName,CanonicalHostedZoneId]" \
        --output text | head -1)

    if [ -n "$alb_info" ]; then
        ALB_DNS=$(echo "$alb_info" | awk '{print $1}')
        ALB_ZONE_ID=$(echo "$alb_info" | awk '{print $2}')
        log_info "✓ Found ALB: $ALB_DNS"
    else
        log_warn "No OpenClaw ALB found"
        echo ""
        echo "Available ALBs:"
        aws elbv2 describe-load-balancers \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[].[LoadBalancerName,DNSName]' \
            --output table

        echo ""
        read -p "Enter ALB DNS name: " ALB_DNS
        read -p "Enter ALB Zone ID: " ALB_ZONE_ID
    fi

    echo "$ALB_DNS"
    echo "$ALB_ZONE_ID"
}

# Create Route53 record
create_dns_record() {
    local alb_dns="$1"
    local alb_zone_id="$2"

    log_step "Creating Route53 DNS Record"

    log_info "Creating A record: $DOMAIN_NAME → $alb_dns"

    # Create change batch JSON
    cat > /tmp/route53-change-batch.json <<EOF
{
  "Comment": "OpenClaw Teams webhook endpoint",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN_NAME",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$alb_zone_id",
          "DNSName": "$alb_dns",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

    # Apply the change
    CHANGE_ID=$(aws route53 change-resource-record-sets \
        --profile "$AWS_PROFILE" \
        --hosted-zone-id "$ZONE_ID" \
        --change-batch file:///tmp/route53-change-batch.json \
        --query 'ChangeInfo.Id' \
        --output text)

    log_info "✓ DNS record change submitted: $CHANGE_ID"

    # Wait for change to propagate
    log_info "Waiting for DNS change to propagate..."

    aws route53 wait resource-record-sets-changed \
        --profile "$AWS_PROFILE" \
        --id "$CHANGE_ID"

    log_info "✓ DNS change propagated"

    # Cleanup
    rm -f /tmp/route53-change-batch.json
}

# Verify DNS resolution
verify_dns() {
    log_step "Verifying DNS Resolution"

    log_info "Checking DNS resolution for $DOMAIN_NAME..."

    sleep 5

    if host "$DOMAIN_NAME" &>/dev/null; then
        local resolved_ip=$(host "$DOMAIN_NAME" | grep "has address" | awk '{print $NF}' | head -1)
        log_info "✓ DNS resolves to: $resolved_ip"
    else
        log_warn "DNS not yet propagated (this can take a few minutes)"
        echo "  Check with: host $DOMAIN_NAME"
    fi
}

# Show completion
show_completion() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "✅ Route53 DNS Record Created"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Domain: $DOMAIN_NAME"
    echo "Points to: $ALB_DNS"
    echo "Zone ID: $ZONE_ID"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Wait for DNS propagation (check with: host $DOMAIN_NAME)"
    echo ""
    echo "2. Request Let's Encrypt certificate:"
    echo "   ./terraform/cert-manager-setup.sh"
    echo ""
    echo "3. Export certificate to ACM:"
    echo "   ./terraform/export-cert-to-acm.sh"
    echo ""
    echo "4. Deploy Terraform infrastructure"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main execution
main() {
    show_banner

    if [ -z "$DOMAIN_NAME" ]; then
        echo "Usage: $0 <domain-name>"
        echo "Example: $0 openclaw.au01-0.dametech.net"
        exit 1
    fi

    find_hosted_zone

    read -a alb_info <<< $(get_alb_dns)
    ALB_DNS="${alb_info[0]}"
    ALB_ZONE_ID="${alb_info[1]}"

    if [ -z "$ALB_DNS" ]; then
        echo "Error: Could not determine ALB DNS name"
        exit 1
    fi

    create_dns_record "$ALB_DNS" "$ALB_ZONE_ID"
    verify_dns

    show_completion
}

# Run main function
main
