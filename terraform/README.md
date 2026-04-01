# OpenClaw Wildcard Edge Terraform

This Terraform stack manages only the shared edge infrastructure needed for Teams-enabled OpenClaw releases.

It does **not** create a new ALB, Kubernetes services, target groups, or per-release listener rules. Those release-specific pieces are handled later by a separate `msteams-enable` workflow.

## What This Stack Does

- reuses the existing shared public ALB
- looks up the existing HTTPS listener on that ALB
- requests a wildcard ACM certificate for `*.openclaw.dametech.net`
- validates that certificate with Route53 DNS records
- attaches the wildcard certificate to the existing HTTPS listener as an additional certificate
- creates a wildcard Route53 alias so `*.openclaw.dametech.net` resolves to the existing ALB

## What This Stack Does Not Do

- create or replace the existing `openclaw.dametech.net` certificate
- create an ALB
- create target groups
- create listener rules for specific releases
- create Kubernetes `Service` resources for Teams webhooks
- configure OpenClaw `channels.msteams`

## Architecture

```text
Azure Bot
    ↓ HTTPS https://<release>.openclaw.dametech.net/api/messages
Existing shared ALB
    ↓ TLS terminated on ALB with wildcard certificate
Future per-release ALB rule
    ↓ HTTP
Release-specific backend service
    ↓
OpenClaw release with Teams enabled
```

## Prerequisites

Before running Terraform:

1. AWS access with permissions for:
   - ACM certificates
   - Route53 records
   - ALB listener certificates
   - ALB and listener reads
2. Existing shared ALB already deployed
3. Existing HTTPS listener already configured on that ALB
4. S3 state backend available:
   - bucket: `dame-terraform-state`
   - lock table: `dame-terraform-locks`

## Configuration

Copy the example file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Example:

```hcl
aws_region                  = "ap-southeast-2"
aws_profile                 = "personal"
environment                 = "prod"
existing_alb_name           = "openclaw-alb"
existing_https_listener_port = 443
route53_zone_name           = "dametech.net"
wildcard_domain_name        = "*.openclaw.dametech.net"
```

## Apply

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Outputs

Key outputs:

- existing ALB DNS name
- existing ALB ARN
- existing HTTPS listener ARN
- wildcard ACM certificate ARN
- wildcard DNS name

## Follow-On Work

After this stack is applied, a separate per-release workflow can:

1. choose a hostname such as `pod-a.openclaw.dametech.net`
2. create a backend Kubernetes `Service` for that release
3. create a target group and host-based ALB listener rule
4. configure `channels.msteams` for that release
5. point the Azure Bot messaging endpoint at that hostname
