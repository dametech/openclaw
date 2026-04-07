# Access to openclaw-ec2

## Overview
The openclaw-ec2 instance can be accessed in two ways:
1. **Direct VPC Access**: Connect directly to <openclaw-private-ip> from any instance in the VPC
2. **SSM Session Manager**: Secure access via AWS Systems Manager (no SSH keys or public IPs needed)

## Instance Details
- **Instance ID**: <YOUR-INSTANCE-ID>
- **Private IP**: <openclaw-private-ip>
- **Region**: ap-southeast-2
- **SSM Status**: Online

## Running Services
- **Port 3978**: Main openclaw gateway (all interfaces)
- **Port 80**: HTTP web server
- **Port 18789, 18791, 18792**: Internal openclaw services (localhost only)

## Security Group Rules
The instance security group (`openclaw-ec2-sg`) allows:
- **Port 443**: From VPC CIDR (<vpc-cidr>) - HTTPS (nginx → OpenClaw Gateway)
- **Port 3978**: From VPC CIDR (<vpc-cidr>) - MS Teams webhook
- **Port 80**: From VPC CIDR (<vpc-cidr>) and ALB - Web server
- **Port 18789**: From VPC CIDR (<vpc-cidr>) - OpenClaw Gateway API (direct)
- **All outbound**: Allowed

## Architecture

**Public Access (MS Teams):**
MS Teams reaches openclaw via:
1. **Internet** → HTTPS (443) → **ALB** (openclaw-alb-56373705.ap-southeast-2.elb.amazonaws.com)
2. **ALB** → HTTP (80) → **EC2** (<openclaw-private-ip>:80)
3. **nginx** → **openclaw** (port 3978)

**VPC Access (Control UI):**
Apps/browsers in VPC access openclaw via:
1. **VPC** → HTTPS (443) → **nginx** (<openclaw-private-ip>:443)
2. **nginx** → **OpenClaw Gateway** (localhost:18789)

**SSL Configuration:**
- Self-signed certificate located at `/etc/nginx/ssl/openclaw.{crt,key}`
- Valid for 365 days
- Subject: CN=<openclaw-private-ip>
- Nginx config: `/etc/nginx/conf.d/openclaw-https.conf`

---

## Method 1: Direct VPC Access (Primary)

Access openclaw directly from any instance in the VPC (<vpc-cidr>):

### From another EC2 instance in the VPC:
```bash
# Test connectivity
curl http://<openclaw-private-ip>:3978

# Or access the web interface
curl http://<openclaw-private-ip>:80
```

### Available from these instances:
- <internal-server> (<internal-ip>)
- <internal-server> (<internal-ip>)
- <firewall> instances (<internal-ip>, <internal-ip>)
- Any other instance in the VPC

### OpenClaw Gateway API & Control UI

**HTTPS Access (Recommended for apps):**
Access the OpenClaw Control UI via HTTPS from within the VPC:

```bash
# Authentication token
TOKEN="<YOUR-OPENCLAW-TOKEN>"

# Access via HTTPS (through nginx)
curl -k -H "Authorization: Bearer $TOKEN" https://<openclaw-private-ip>/

# Make API calls via HTTPS
curl -k -H "Authorization: Bearer $TOKEN" https://<openclaw-private-ip>/api/agents
```

**Web UI Access:**
Open in browser: `https://<openclaw-private-ip>` (requires VPN connection)

**Note:** The SSL certificate is self-signed, so you'll need to accept the security warning in your browser or use `-k` flag with curl.

**Direct Gateway Access (HTTP):**
You can also access the gateway directly on port 18789:
```bash
# Direct HTTP access
curl -H "Authorization: Bearer $TOKEN" http://<openclaw-private-ip>:18789/
```

---

## Method 2: SSM Session Manager (For local access)

## Quick Start

### Option 1: Use the provided script (Recommended)
```bash
# Forward openclaw gateway (port 3978)
./connect-openclaw.sh

# Forward HTTP web server (port 80)
./connect-openclaw.sh 8080 80

# Custom port forwarding
./connect-openclaw.sh <local-port> <remote-port>
```

### Option 2: Manual SSM port forwarding
```bash
# Forward port 3978 (openclaw gateway)
aws ssm start-session \
    --region ap-southeast-2 \
    --target <YOUR-INSTANCE-ID> \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["3978"],"localPortNumber":["3978"]}'

# Forward port 80 (web interface)
aws ssm start-session \
    --region ap-southeast-2 \
    --target <YOUR-INSTANCE-ID> \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'
```

### Option 3: Interactive shell access
```bash
aws ssm start-session \
    --region ap-southeast-2 \
    --target <YOUR-INSTANCE-ID>
```

## Prerequisites
1. AWS CLI installed and configured
2. Session Manager plugin installed ([Installation Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html))
3. IAM permissions for SSM (already configured on the instance)

## Verify Session Manager Plugin
```bash
session-manager-plugin --version
```

If not installed:
```bash
# macOS
brew install --cask session-manager-plugin

# Or download from AWS
# https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

## Access URLs (after port forwarding)
- openclaw gateway: http://localhost:3978
- Web interface: http://localhost:8080 (if forwarding port 80 to 8080)

## Troubleshooting

### Check if instance is online
```bash
aws ssm describe-instance-information \
    --region ap-southeast-2 \
    --filters "Key=InstanceIds,Values=<YOUR-INSTANCE-ID>"
```

### Check running processes
```bash
aws ssm start-session \
    --region ap-southeast-2 \
    --target <YOUR-INSTANCE-ID> \
    --document-name AWS-StartNonInteractiveCommand \
    --parameters '{"command":["ps aux | grep openclaw"]}'
```

### Check listening ports
```bash
aws ssm start-session \
    --region ap-southeast-2 \
    --target <YOUR-INSTANCE-ID> \
    --document-name AWS-StartNonInteractiveCommand \
    --parameters '{"command":["ss -tlnp"]}'
```
