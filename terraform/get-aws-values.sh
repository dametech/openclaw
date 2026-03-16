#!/bin/bash
#
# Get AWS Resource Values for Terraform Configuration
# Run this to gather all required values for terraform.tfvars
#

set -e

REGION="ap-southeast-2"
PROFILE="personal"

echo "╔═══════════════════════════════════════════════╗"
echo "║   OpenClaw Terraform Values Collection       ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# VPC ID
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. VPC ID (DAME-VPC)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
VPC_ID=$(aws ec2 describe-vpcs \
  --profile "$PROFILE" \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=*DAME*" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$VPC_ID" != "NOT_FOUND" ]; then
    echo "vpc_id = \"$VPC_ID\""
else
    echo "# VPC not found - list all VPCs:"
    aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" \
      --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output table
fi

echo ""

# Public Subnets
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Public Subnet IDs (need at least 2 in different AZs)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$VPC_ID" != "NOT_FOUND" ]; then
    echo "public_subnet_ids = ["
    aws ec2 describe-subnets \
      --profile "$PROFILE" \
      --region "$REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'Subnets[].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' \
      --output text | while read subnet az public name; do
        if [ "$public" = "True" ]; then
            echo "  \"$subnet\",  # $az - $name"
        fi
    done
    echo "]"
else
    echo "# VPC_ID required to list subnets"
fi

echo ""

# ACM Certificates
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. ACM Certificate ARN (for HTTPS)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CERTS=$(aws acm list-certificates \
  --profile "$PROFILE" \
  --region "$REGION" \
  --query 'CertificateSummaryList[].[CertificateArn,DomainName,Status]' \
  --output text 2>/dev/null)

if [ -n "$CERTS" ]; then
    echo "$CERTS" | while read arn domain status; do
        if [ "$status" = "ISSUED" ]; then
            echo "acm_certificate_arn = \"$arn\"  # $domain"
        fi
    done
else
    echo "# No ACM certificates found"
    echo "# Create one with: aws acm request-certificate --domain-name your-domain.com"
fi

echo ""

# Kubernetes Nodes
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Kubernetes Worker Node IPs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f ~/.kube/au01-0.yaml ]; then
    echo "k8s_worker_nodes = ["
    export KUBECONFIG=~/.kube/au01-0.yaml
    kubectl get nodes -o wide | grep -E "worker" | grep -v "SchedulingDisabled" | while read name status roles age version internal external os kernel runtime; do
        echo "  \"$internal\",  # $name"
    done
    echo "]"
else
    echo "# Kubeconfig not found at ~/.kube/au01-0.yaml"
fi

echo ""

# Route53 (optional)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Route53 Configuration (Optional - for custom domain)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ZONES=$(aws route53 list-hosted-zones \
  --profile "$PROFILE" \
  --query 'HostedZones[].[Id,Name]' \
  --output text 2>/dev/null)

if [ -n "$ZONES" ]; then
    echo "# Available hosted zones:"
    echo "$ZONES" | while read id name; do
        ZONE_ID=$(echo $id | cut -d'/' -f3)
        echo "# route53_zone_id = \"$ZONE_ID\"  # $name"
    done
    echo "# domain_name = \"openclaw.yourdomain.com\""
    echo "# create_route53_record = true"
else
    echo "# No Route53 hosted zones found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Copy the values above into terraform.tfvars"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Then run:"
echo "  cd terraform"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo ""
