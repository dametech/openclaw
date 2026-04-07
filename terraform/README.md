# OpenClaw Wildcard Edge Terraform

This Terraform stack manages the shared public edge for Teams-enabled OpenClaw releases.

It does **not** create a new ALB or any release-specific AWS routing. Release-specific Kubernetes services and `Ingress` objects are handled later by `setup-msteams-integration.sh`.

## What This Stack Does

- reuses the existing shared public ALB
- looks up the existing HTTPS listener on that ALB
- requests a wildcard ACM certificate for `*.openclaw.dametech.net`
- validates that certificate with Route53 DNS records
- attaches the wildcard certificate to the existing HTTPS listener as an additional certificate
- creates a wildcard Route53 alias so `*.openclaw.dametech.net` resolves to the existing ALB
- creates one shared target group for ingress-nginx
- registers ingress-nginx private IP targets
- creates one shared listener rule forwarding wildcard OpenClaw hosts to ingress-nginx

## What This Stack Does Not Do

- create or replace the existing `openclaw.dametech.net` certificate
- create an ALB
- create listener rules for specific releases
- create Kubernetes `Service` resources for Teams webhooks
- configure OpenClaw `channels.msteams`

## Architecture

```text
Azure Bot
    ↓ HTTPS https://<release>.openclaw.dametech.net/api/messages
Existing shared ALB
    ↓ TLS terminated on ALB with wildcard certificate
Shared ALB rule
    ↓ HTTP
ingress-nginx
    ↓ host/path routing
Release-specific Teams service
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
   - ALB target groups and target registration
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
ingress_target_ips          = ["10.42.32.210"]
```

### `ingress_target_ips`

`ingress_target_ips` is the list of IPs that the shared ALB wildcard target group should register and forward traffic to.

For this stack, those IPs should be the stable `ingress-nginx` entrypoint IPs that the ALB can reach on port `80`. In this environment, that is typically the `EXTERNAL-IP` exposed by the `ingress-nginx-controller` service.

Do not use arbitrary OpenClaw pod IPs here. Do not prefer the `ingress-nginx` controller pod IP unless your network is intentionally routing ALB traffic directly to pod CIDRs and you accept that pod IPs can change after reschedules.

Preferred value:

- the `EXTERNAL-IP` of `ingress-nginx-controller` when it is reachable from the ALB network

Avoid unless you know the network path supports it:

- individual ingress controller pod IPs from `kubectl get pods -o wide`
- application pod IPs

### How To Find `ingress_target_ips`

List the ingress controller service:

```bash
kubectl get svc -n ingress-nginx
```

Example output:

```text
NAME                     TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)
ingress-nginx-controller LoadBalancer   10.102.81.96    10.42.32.210   80:30734/TCP,443:32545/TCP
```

In that case, use:

```hcl
ingress_target_ips = [
  "10.42.32.210",
]
```

You can also inspect the service in a more targeted way:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o wide
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[*].ip}'
echo
```

The service endpoints are useful for understanding where traffic goes after it hits the service, but they are usually not the value you should place into `ingress_target_ips`:

```bash
kubectl get endpoints -n ingress-nginx ingress-nginx-controller -o wide
kubectl get pods -n ingress-nginx -o wide
```

If the endpoints show something like `10.244.4.32:80`, that is the ingress controller pod IP. That is useful for debugging, but in most cases the better Terraform input is the ingress service IP such as `10.42.32.210`.

### Verification

After applying Terraform, verify that the wildcard target group actually has registered targets:

```bash
aws elbv2 describe-target-health --target-group-arn <WILDCARD_TARGET_GROUP_ARN>
```

If the target group is empty, check:

- `terraform.tfvars` contains the expected `ingress_target_ips`
- the chosen IP is reachable from the ALB network
- the ingress service is answering on port `80`

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
- shared ingress target group ARN

## Follow-On Work

After this stack is applied, a separate per-release workflow can:

1. choose a hostname such as `pod-a.openclaw.dametech.net`
2. create a backend Kubernetes `Service` for that release
3. create a Kubernetes `Ingress` for that hostname and `/api/messages`
4. configure `channels.msteams` for that release
5. point the Azure Bot messaging endpoint at that hostname
