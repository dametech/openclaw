# OpenClaw Teams Integration - Terraform Infrastructure

This Terraform configuration extends your existing ALB to route Microsoft Teams webhooks to the OpenClaw pod running on your Kubernetes cluster.

## Architecture

```
Internet (HTTPS:443)
    ↓
openclaw-alb-56373705.ap-southeast-2.elb.amazonaws.com
    ↓
ALB Listener Rule: /api/messages → K8s Target Group
    ↓
Kubernetes Worker Nodes (NodePort 30978)
    ↓
OpenClaw Pod (port 3978)
```

### Components

1. **Existing ALB** - `openclaw-alb-56373705` in DAME-VPC
2. **Target Group** - Routes to Kubernetes worker node IPs
3. **Listener Rule** - Matches `/api/messages` path
4. **NodePort Service** - Exposes port 3978 on all K8s nodes
5. **Security Group** - Allows ALB → K8s node traffic

## Prerequisites

Before running Terraform:

1. **AWS Access**
   - AWS CLI configured with `personal` profile
   - Permissions to manage ALB, Target Groups, Security Groups

2. **Existing Resources**
   - ALB: `openclaw-alb-56373705.ap-southeast-2.elb.amazonaws.com`
   - VPC: DAME-VPC
   - HTTPS listener on ALB (port 443)

3. **Kubernetes Access**
   - Kubeconfig: `~/.kube/au01-0.yaml`
   - Cluster: au01-0 (Talos)
   - OpenClaw deployed in `openclaw` namespace

4. **S3 Backend**
   - S3 bucket: `<your-tf-state-bucket>`
   - DynamoDB table: `<your-tf-locks-table>` (for state locking)

## Quick Start

### 1. Get Kubernetes Node IPs

```bash
export KUBECONFIG=~/.kube/au01-0.yaml
kubectl get nodes -o wide

# Note the INTERNAL-IP addresses of worker nodes
# Example: 10.42.32.15, 10.42.32.20, etc.
```

### 2. Get AWS Resource IDs

```bash
# Get VPC ID
aws ec2 describe-vpcs --profile personal --region ap-southeast-2 \
  --filters "Name=tag:Name,Values=DAME-VPC" \
  --query 'Vpcs[0].VpcId' --output text

# Get ALB ARN
aws elbv2 describe-load-balancers --profile personal --region ap-southeast-2 \
  --names openclaw-alb \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text

# Get HTTPS Listener ARN
ALB_ARN=$(aws elbv2 describe-load-balancers --profile personal --region ap-southeast-2 \
  --names openclaw-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)

aws elbv2 describe-listeners --profile personal --region ap-southeast-2 \
  --load-balancer-arn $ALB_ARN \
  --query 'Listeners[?Port==`443`].ListenerArn' --output text
```

### 3. Configure Variables

Copy the example file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your actual values:
```hcl
vpc_id           = "vpc-0abc123def456"
alb_arn          = "arn:aws:elasticloadbalancing:..."
alb_listener_arn = "arn:aws:elasticloadbalancing:..."

k8s_worker_nodes = [
  "10.42.32.15",
  "10.42.32.20",
  "10.42.32.25",
  "10.42.32.30"
]
```

### 4. Initialize Terraform

```bash
cd terraform
terraform init
```

This will:
- Configure S3 backend for state storage
- Download required providers (AWS, Kubernetes)

### 5. Plan Infrastructure Changes

```bash
terraform plan
```

Review the plan carefully. It will create:
- Target Group for K8s nodes
- 4 Target Group Attachments (one per node)
- ALB Listener Rule for `/api/messages`
- Security Group for ALB → K8s traffic
- Kubernetes NodePort Service

### 6. Apply Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

### 7. Get Webhook URL

```bash
terraform output teams_webhook_url
```

Use this URL as your **Azure Bot messaging endpoint**.

## What Gets Created

### AWS Resources

1. **Target Group**: `oc-k8s-*`
   - Protocol: HTTP
   - Port: NodePort (30978)
   - Targets: Kubernetes worker node IPs
   - Health check: Port 18789, path `/`

2. **Target Group Attachments**
   - One per Kubernetes worker node
   - Registers node IP:NodePort as target

3. **ALB Listener Rule**
   - Priority: 100
   - Condition: Path `/api/messages`
   - Action: Forward to K8s target group

4. **Security Group**: `openclaw-k8s-alb-ingress`
   - Allows ALB → K8s nodes on NodePort
   - Allows ALB → K8s nodes on port 18789 (health checks)

### Kubernetes Resources

1. **Service**: `openclaw-teams-webhook`
   - Type: NodePort
   - Port: 3978 → NodePort 30978
   - Selector: `app.kubernetes.io/name=openclaw`
   - Session affinity: ClientIP (3 hour timeout)

## Configuration Updates Needed

### Update OpenClaw Helm Values

Add Teams webhook port exposure:

```yaml
app-template:
  service:
    main:
      ports:
        http:
          port: 18789
        teams-webhook:
          port: 3978
          protocol: TCP
```

### Update openclaw.json

After deploying infrastructure, configure Teams in OpenClaw:

```json
{
  "channels": {
    "msteams": {
      "enabled": true,
      "appId": "${MSTEAMS_APP_ID}",
      "appPassword": "${MSTEAMS_APP_PASSWORD}",
      "tenantId": "${MSTEAMS_TENANT_ID}",
      "webhook": {
        "port": 3978,
        "path": "/api/messages"
      },
      "dmPolicy": "pairing",
      "groupPolicy": "open"
    }
  }
}
```

## Validation

### 1. Check Target Group Health

```bash
aws elbv2 describe-target-health --profile personal --region ap-southeast-2 \
  --target-group-arn $(terraform output -raw target_group_arn)
```

All targets should show `State: healthy`.

### 2. Test Webhook Endpoint

```bash
WEBHOOK_URL=$(terraform output -raw teams_webhook_url)

curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"type":"message","text":"test"}'
```

Should return 200 OK (not 404 or 502).

### 3. Check Kubernetes Service

```bash
export KUBECONFIG=~/.kube/au01-0.yaml
kubectl get svc openclaw-teams-webhook -n openclaw
kubectl describe svc openclaw-teams-webhook -n openclaw
```

### 4. Test from Worker Node

SSH to a worker node and test locally:

```bash
curl http://localhost:30978/api/messages
```

## Monitoring

### CloudWatch Metrics

Monitor these metrics in CloudWatch:
- `TargetResponseTime` - Webhook latency
- `HealthyHostCount` - Number of healthy K8s nodes
- `UnHealthyHostCount` - Unhealthy targets
- `RequestCount` - Teams webhook volume

### Kubernetes Logs

```bash
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main -f | grep -i "teams\|webhook"
```

## Troubleshooting

### Unhealthy Targets

**Symptoms**: Target group shows unhealthy targets

**Check**:
```bash
# Verify NodePort service exists
kubectl get svc openclaw-teams-webhook -n openclaw

# Check pod is running
kubectl get pods -n openclaw

# Test health endpoint locally on node
# (requires node SSH access)
```

**Solutions**:
- Verify NodePort matches Terraform variable
- Check Security Group allows traffic
- Ensure OpenClaw pod is running
- Verify health check port (18789) is accessible

### 502 Bad Gateway

**Symptoms**: Webhook returns 502

**Solutions**:
- Check target health status
- Verify OpenClaw is listening on port 3978
- Check Kubernetes service endpoints
- Review ALB access logs

### 404 Not Found

**Symptoms**: Webhook returns 404

**Solutions**:
- Verify `/api/messages` path is correct
- Check Teams plugin is installed in OpenClaw
- Ensure `channels.msteams` is configured
- Verify webhook.path matches ALB rule

## Maintenance

### Adding/Removing Nodes

When adding Kubernetes nodes:

1. Add node IP to `terraform.tfvars`:
   ```hcl
   k8s_worker_nodes = [
     "10.42.32.15",
     "10.42.32.20",
     "10.42.32.25",
     "10.42.32.30",
     "10.42.32.35"  # New node
   ]
   ```

2. Apply changes:
   ```bash
   terraform plan
   terraform apply
   ```

### Rotating Client Secrets

When rotating Azure Bot client secret:

1. Create new secret in Azure App Registration
2. Update 1Password with new secret
3. Update Kubernetes secret:
   ```bash
   kubectl create secret generic openclaw-teams-credentials \
     --from-literal=MSTEAMS_APP_PASSWORD="NEW_SECRET" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
4. Restart OpenClaw pod:
   ```bash
   kubectl rollout restart deployment/openclaw -n openclaw
   ```

### Destroying Infrastructure

To remove Teams integration:

```bash
terraform destroy
```

This will:
- Remove ALB listener rule
- Delete target group and attachments
- Remove security group
- Delete Kubernetes NodePort service

⚠️ This does NOT delete the Azure Bot or App Registration (manual cleanup required).

## Cost Considerations

**AWS Costs:**
- ALB: Already running (no additional cost)
- Target Group: Minimal (covered by ALB pricing)
- Data transfer: Standard ALB → EC2/K8s rates

**No additional AWS charges** if ALB already exists.

## Security Notes

1. **TLS Termination**: ALB handles HTTPS, routes HTTP to K8s
2. **Security Group**: Restricts K8s node access to ALB only
3. **Session Affinity**: ClientIP ensures conversation continuity
4. **Health Checks**: Monitors pod availability
5. **Credentials**: Store in 1Password, reference in K8s secrets

## Next Steps

After deploying infrastructure:

1. Configure Azure Bot messaging endpoint (use `teams_webhook_url` output)
2. Install Teams plugin in OpenClaw pod
3. Configure Teams credentials in openclaw.json
4. Create and upload Teams app manifest
5. Test webhook connectivity
6. Approve pairing in Teams

See `docs/TEAMS-SETUP.md` for complete integration guide.

---

**Managed by**: Terraform
**State Backend**: S3 (`<your-tf-state-bucket>/openclaw/teams-alb/`)
**Provider Versions**: AWS ~> 5.0, Kubernetes ~> 2.0
