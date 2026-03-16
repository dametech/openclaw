# Microsoft Teams Deployment Plan

## Current Status

- ✅ Slack integration working
- ✅ cert-manager installed in cluster
- ✅ Terraform infrastructure code created
- ⏸️ Let's Encrypt cert blocked by nginx ingress validation

## Simplified Deployment Approach

Given the complexity of cert-manager HTTP-01 challenges, here's a phased approach:

### Phase 1: Deploy Infrastructure (HTTP Only for Testing)

1. **Deploy Terraform without HTTPS** (Skip certificate for now)
2. **Use HTTP ALB** for initial Teams webhook testing
3. **Verify Teams integration works**
4. **Then add TLS** in Phase 2

### Phase 2: Add TLS (Choose One Method)

**Option A: Manual certbot (Simplest)**
- Run certbot locally with DNS challenge
- Upload cert to ACM manually
- Update Terraform to use HTTPS

**Option B: AWS Certificate Manager Request (Easiest)**
- Request certificate directly in ACM (not Let's Encrypt)
- ACM handles renewal automatically
- Simpler than cert-manager integration

**Option C: Fix cert-manager (Most Complex)**
- Configure DNS-01 challenge with Route53 credentials
- Or fix nginx ingress webhook to allow HTTP-01

## Recommended: Start with HTTP, Add TLS Later

### Step 1: Simplify Terraform

Remove TLS requirement temporarily:

```hcl
# In main.tf - comment out HTTPS listener
# resource "aws_lb_listener" "https" {
#   ...
# }

# Use HTTP listener as default
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.openclaw.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openclaw_k8s_teams.arn
  }
}
```

### Step 2: Deploy Infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars (no ACM cert needed)
terraform init
terraform plan
terraform apply
```

### Step 3: Test Teams Webhook (HTTP)

```bash
# Get ALB URL
terraform output teams_webhook_url

# Should be: http://openclaw-teams-alb-xxx.ap-southeast-2.elb.amazonaws.com/api/messages
```

Use this HTTP URL in Azure Bot (temporarily)

### Step 4: Add TLS (After Teams Works)

Once Teams integration is working over HTTP, add HTTPS:

**Quick Option - ACM Certificate:**
```bash
# Request cert in ACM for your domain
aws acm request-certificate \
  --domain-name openclaw.au01-0.dametech.net \
  --validation-method DNS \
  --region ap-southeast-2 \
  --profile personal

# ACM will give you DNS records to add to Route53
# Once validated, update terraform.tfvars with cert ARN
# Uncomment HTTPS listener in main.tf
# terraform apply
```

## Alternative: Use Existing Domain/Cert

Do you already have:
- A wildcard certificate for `*.dametech.net`?
- An existing ACM certificate you can use?

This would be the fastest path!

## Decision Point

Which approach do you prefer:

1. **Deploy HTTP now, add TLS later** (fastest to test Teams)
2. **Request ACM certificate now** (DNS validation, ~5-30 min)
3. **Fix cert-manager DNS-01** (requires AWS creds, more complex)
4. **Use existing cert** (if you have one)

What would you like to do?
