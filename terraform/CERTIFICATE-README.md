# Let's Encrypt Certificate Management

This directory contains scripts and configurations for managing Let's Encrypt certificates with cert-manager and syncing them to AWS ACM for use with the ALB.

## Architecture

```
cert-manager (Kubernetes)
    ↓
Let's Encrypt ACME Challenge (HTTP-01)
    ↓
Certificate stored in K8s Secret (openclaw-tls-secret)
    ↓
CronJob exports cert → AWS ACM
    ↓
ALB uses ACM certificate for HTTPS
```

## Why This Approach?

- **Free certificates** from Let's Encrypt
- **Auto-renewal** via cert-manager (before 90-day expiry)
- **Kubernetes-native** certificate management
- **Works with ALB** via ACM sync
- **No manual certificate generation** required

## Quick Start

### 1. Install cert-manager and Request Certificate

```bash
./terraform/cert-manager-setup.sh
```

This will:
- Install cert-manager v1.16.2 in Kubernetes
- Create Let's Encrypt ClusterIssuers (staging + prod)
- Request a certificate for your domain
- Wait for certificate to be issued

**What you need:**
- Domain name (e.g., `openclaw.yourdomain.com`)
- Email address for Let's Encrypt notifications
- DNS pointing to your ALB (can add after cert is created)

### 2. Export Certificate to ACM

```bash
./terraform/export-cert-to-acm.sh
```

This will:
- Extract certificate from Kubernetes secret
- Upload to AWS Certificate Manager (ACM)
- Save ARN to `/tmp/openclaw-acm-cert-arn.txt`
- Display ARN for terraform.tfvars

**What you need:**
- AWS CLI configured with `personal` profile
- Permissions: `acm:ImportCertificate`, `acm:ListCertificates`, `acm:DeleteCertificate`

### 3. Setup Auto-Renewal

```bash
./terraform/setup-cert-renewal.sh
```

This will:
- Create Kubernetes CronJob (runs daily at 3 AM UTC)
- Configure AWS credentials for CronJob
- Test manual sync
- Monitor certificate expiry

**What you need:**
- AWS credentials for CronJob (access key or IRSA)
- Permissions: `acm:ImportCertificate`

## Manual Certificate Management

### Create Certificate Manually

Edit `k8s-certificate.yaml` and update:
- Domain name: `openclaw.yourdomain.com`
- Email: `your-email@example.com`
- Issuer: `letsencrypt-staging` or `letsencrypt-prod`

Apply:
```bash
export KUBECONFIG=~/.kube/au01-0.yaml
kubectl apply -f terraform/k8s-certificate.yaml
```

### Check Certificate Status

```bash
# View certificate
kubectl get certificate openclaw-tls -n openclaw

# Detailed status
kubectl describe certificate openclaw-tls -n openclaw

# Check certificate request
kubectl get certificaterequest -n openclaw

# View ACME challenge
kubectl get challenge -n openclaw
```

### Certificate States

**Pending:**
```
Status:
  Conditions:
    Type:    Issuing
    Status:  True
    Reason:  Validating
```

**Ready:**
```
Status:
  Conditions:
    Type:    Ready
    Status:  True
```

**Failed:**
```
Status:
  Conditions:
    Type:    Ready
    Status:  False
    Reason:  Failed
    Message: <error details>
```

### Troubleshoot Certificate Issues

**Certificate stuck in Pending:**

```bash
# Check ACME challenge
kubectl describe challenge -n openclaw

# Common issues:
# - DNS not pointing to correct IP
# - Firewall blocking port 80
# - Ingress class not configured
```

**ACME Challenge Failing:**

```bash
# View challenge logs
kubectl logs -n cert-manager -l app=cert-manager

# Check if HTTP-01 endpoint is accessible
curl http://your-domain.com/.well-known/acme-challenge/test
```

## Certificate Renewal

### Automatic Renewal

cert-manager automatically renews certificates **30 days before expiry** (configurable via `renewBefore`).

The CronJob syncs the renewed certificate to ACM daily.

### Manual Renewal

Force renewal:

```bash
# Delete certificate to trigger re-issue
kubectl delete certificate openclaw-tls -n openclaw

# Re-create from YAML
kubectl apply -f terraform/k8s-certificate.yaml

# Or update renewal annotation
kubectl annotate certificate openclaw-tls \
  -n openclaw \
  cert-manager.io/issue-temporary-certificate="true"
```

### Monitor Renewal Status

```bash
# Check certificate expiry
kubectl get certificate openclaw-tls -n openclaw -o jsonpath='{.status.notAfter}'

# Check renewal timestamp
kubectl get secret openclaw-tls-secret -n openclaw -o yaml | grep -A5 metadata

# View cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f
```

## ACM Sync CronJob

### View CronJob Status

```bash
# List CronJobs
kubectl get cronjobs -n openclaw

# View recent jobs
kubectl get jobs -n openclaw -l cronjob=openclaw-cert-sync-acm

# View logs from last sync
kubectl logs -l job-name=$(kubectl get jobs -n openclaw -l cronjob=openclaw-cert-sync-acm --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}') -n openclaw
```

### Manual Sync

```bash
# Trigger manual sync
kubectl create job openclaw-cert-sync-manual \
  --from=cronjob/openclaw-cert-sync-acm \
  -n openclaw

# Watch logs
kubectl logs -f job/openclaw-cert-sync-manual -n openclaw
```

### Update CronJob Schedule

```bash
# Edit CronJob
kubectl edit cronjob openclaw-cert-sync-acm -n openclaw

# Change schedule (cron syntax)
# Default: "0 3 * * *" (daily at 3 AM UTC)
# Hourly: "0 * * * *"
# Twice daily: "0 */12 * * *"
```

## Security

### AWS Credentials

**Option 1: IAM Role for Service Accounts (IRSA) - Recommended**

Requires EKS with OIDC provider. Not applicable for non-EKS clusters.

**Option 2: AWS Access Keys**

Store in Kubernetes secret:
```bash
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=AKIAXXXXXXXX \
  --from-literal=AWS_SECRET_ACCESS_KEY=xxxx \
  --from-literal=AWS_DEFAULT_REGION=ap-southeast-2 \
  -n openclaw
```

**Best Practice:** Create dedicated IAM user with minimal permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "acm:ImportCertificate",
        "acm:ListCertificates",
        "acm:DescribeCertificate"
      ],
      "Resource": "*"
    }
  ]
}
```

### Certificate Storage

- **Kubernetes Secret**: Encrypted at rest (if configured)
- **ACM**: Managed by AWS, encrypted by default
- **Temp files**: Cleaned up immediately after export

## Costs

**cert-manager:**
- Free (open-source)

**Let's Encrypt:**
- Free certificates
- Rate limit: 50 certs per domain per week

**AWS ACM:**
- Free to store certificates
- No charge for certificates used with ALB

**Total cost**: $0 for certificates

## Troubleshooting

### ACM Import Fails

**Error**: "ValidationException: Invalid certificate"

**Solutions:**
- Ensure certificate is PEM format
- Check private key matches certificate
- Verify certificate isn't expired
- Check certificate chain is complete

### CronJob Fails

**Check logs:**
```bash
kubectl get jobs -n openclaw
kubectl logs -l cronjob=openclaw-cert-sync-acm -n openclaw --tail=50
```

**Common issues:**
- AWS credentials invalid/expired
- Permissions insufficient
- Secret doesn't exist
- Certificate not ready

### Certificate Not Renewing

**Check cert-manager:**
```bash
kubectl logs -n cert-manager -l app=cert-manager | grep openclaw-tls
```

**Force renewal:**
```bash
kubectl delete certificate openclaw-tls -n openclaw
kubectl apply -f terraform/k8s-certificate.yaml
```

## Alternative: Certbot (Without cert-manager)

If you prefer not to use cert-manager:

```bash
# Install certbot
brew install certbot  # macOS
# or
apt-get install certbot  # Linux

# Get certificate (DNS challenge)
certbot certonly --manual --preferred-challenges dns \
  -d openclaw.yourdomain.com

# Certificate files at: /etc/letsencrypt/live/openclaw.yourdomain.com/
# - fullchain.pem (certificate + chain)
# - privkey.pem (private key)

# Upload to ACM
aws acm import-certificate \
  --profile personal \
  --region ap-southeast-2 \
  --certificate fileb:///etc/letsencrypt/live/openclaw.yourdomain.com/fullchain.pem \
  --private-key fileb:///etc/letsencrypt/live/openclaw.yourdomain.com/privkey.pem
```

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [AWS ACM User Guide](https://docs.aws.amazon.com/acm/latest/userguide/)
- [cert-manager HTTP-01 Challenge](https://cert-manager.io/docs/configuration/acme/http01/)

---

**Last Updated**: March 2026
**cert-manager Version**: v1.16.2
