# OpenClaw EC2 Instance Setup Summary

## Date
2026-03-16

## Instance Details
- **Instance ID**: i-0f6dac37c87940ba9
- **Instance Name**: openclaw-ec2
- **Instance Type**: t3.medium
- **Private IP**: 10.0.2.162
- **Region**: ap-southeast-2
- **VPC**: DAME-AWS-VPC (vpc-0b0b6cebfa4d51b5b, 10.0.0.0/16)

---

## Changes Made

### 1. Security Group Configuration
**Security Group**: sg-073302608b92c1769 (openclaw-ec2-sg)

**Added Rules:**
- **Port 443** (HTTPS): From VPC CIDR 10.0.0.0/16
  - Purpose: HTTPS access to OpenClaw Control UI via nginx
- **Port 3978** (TCP): From VPC CIDR 10.0.0.0/16
  - Purpose: MS Teams webhook (already existed, verified)
- **Port 80** (HTTP): From VPC CIDR 10.0.0.0/16 and ALB
  - Purpose: Web server (already existed, verified)
- **Port 18789** (TCP): From VPC CIDR 10.0.0.0/16
  - Purpose: Direct OpenClaw Gateway API access

### 2. SSL Certificate Generation
**Location**: /etc/nginx/ssl/

**Files Created:**
- `/etc/nginx/ssl/openclaw.crt` - Self-signed SSL certificate
- `/etc/nginx/ssl/openclaw.key` - Private key

**Certificate Details:**
- Type: Self-signed X.509 certificate
- Key Size: RSA 2048-bit
- Validity: 365 days
- Subject: C=AU, ST=NSW, L=Sydney, O=DAME, CN=10.0.2.162
- Subject Alternative Name: IP:10.0.2.162

### 3. Nginx HTTPS Configuration
**File Created**: `/etc/nginx/conf.d/openclaw-https.conf`

**Configuration:**
```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    "" close;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name 10.0.2.162;

    ssl_certificate /etc/nginx/ssl/openclaw.crt;
    ssl_certificate_key /etc/nginx/ssl/openclaw.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    # Proxy to OpenClaw Gateway
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;

        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Pass through Authorization header
        proxy_pass_request_headers on;
    }
}
```

**Service**: nginx reloaded successfully

### 4. OpenClaw Gateway Configuration
**File Modified**: `/home/ssm-user/.openclaw/openclaw.json`

**Backups Created:**
- `openclaw.json.bak.vpn`
- `openclaw.json.bak.origins`
- `openclaw.json.bak.https`
- `openclaw.json.bak.pairing`
- `openclaw.json.bak.proxy`
- `openclaw.json.bak.<timestamp>`

**Changes Made:**

1. **Gateway Bind Mode:**
   - Changed from: `"bind": "loopback"`
   - Changed to: `"bind": "lan"` (listens on 0.0.0.0)
   - Applied using: `openclaw doctor --fix`

2. **Allowed Origins:**
   - Added: `https://10.0.2.162`
   - Added: `http://10.0.2.162:18789`
   - Existing: `http://localhost:18789`
   - Existing: `http://127.0.0.1:18789`

3. **Trusted Proxies:**
   - Added: `["127.0.0.1", "::1"]`
   - Purpose: Trust nginx proxy for proper client IP detection

**Final Gateway Configuration:**
```json
"gateway": {
  "port": 18789,
  "mode": "local",
  "bind": "lan",
  "controlUi": {
    "allowedOrigins": [
      "http://10.0.2.162:18789",
      "http://127.0.0.1:18789",
      "http://localhost:18789",
      "https://10.0.2.162"
    ]
  },
  "auth": {
    "mode": "token",
    "token": "9e56f4da7659390a5791329ff3c542452f500219e2178e00"
  },
  "trustedProxies": [
    "127.0.0.1",
    "::1"
  ],
  "tailscale": {
    "mode": "off",
    "resetOnExit": false
  },
  "nodes": {
    "denyCommands": [
      "camera.snap",
      "camera.clip",
      "screen.record",
      "calendar.add",
      "contacts.add",
      "reminders.add"
    ]
  }
}
```

**Service**: openclaw.service restarted successfully

### 5. Device Pairing
**Command Used**: `openclaw devices approve <request-id>`

**Device Approved:**
- Device ID: `263906cbc6e25034717b0e5cc8666dd62983f8580e6313cb4def20497d251576`
- Request ID: `1030abe6-e097-4a4c-b3d2-04d246f22443`
- Role: operator
- Scopes: operator.admin, operator.approvals, operator.pairing

**Total Paired Devices**: 3

---

## Access Information

### Control UI Access (VPC-only, HTTPS)

**Primary URL:**
```
https://10.0.2.162/?token=9e56f4da7659390a5791329ff3c542452f500219e2178e00
```

**Helper Script:**
```bash
./get-openclaw-url.sh
```

**SSL Certificate Note:**
- Self-signed certificate requires accepting browser security warning
- For apps: disable SSL verification or add cert to trusted store

### API Access

**HTTPS (Recommended):**
```bash
curl -k \
  -H "Authorization: Bearer 9e56f4da7659390a5791329ff3c542452f500219e2178e00" \
  https://10.0.2.162/api/agents
```

**HTTP Direct:**
```bash
curl -H "Authorization: Bearer 9e56f4da7659390a5791329ff3c542452f500219e2178e00" \
  http://10.0.2.162:18789/api/agents
```

### Gateway Token
```
9e56f4da7659390a5791329ff3c542452f500219e2178e00
```

---

## Architecture

### Public Access (MS Teams)
1. **Internet** → HTTPS (443) → **ALB** (openclaw-alb-56373705.ap-southeast-2.elb.amazonaws.com)
2. **ALB** → HTTP (80) → **EC2** nginx (10.0.2.162:80)
3. **nginx** → **openclaw** MS Teams webhook (localhost:3978)

### VPC Access (Control UI & API)
1. **VPC** → HTTPS (443) → **nginx** (10.0.2.162:443)
2. **nginx** → **OpenClaw Gateway** (localhost:18789)

### Direct Gateway Access (VPC-only, HTTP)
1. **VPC** → HTTP (18789) → **OpenClaw Gateway** (10.0.2.162:18789)

---

## Port Summary

| Port  | Protocol | Access From        | Purpose                           | SSL |
|-------|----------|-------------------|-----------------------------------|-----|
| 443   | HTTPS    | VPC (10.0.0.0/16) | Control UI & API via nginx        | ✓   |
| 80    | HTTP     | VPC + ALB         | MS Teams webhook via nginx        | -   |
| 3978  | HTTP     | VPC (10.0.0.0/16) | MS Teams Bot Framework endpoint   | -   |
| 18789 | HTTP     | VPC (10.0.0.0/16) | Direct OpenClaw Gateway API       | -   |

---

## Scripts Created

### 1. get-openclaw-url.sh
Returns the complete Control UI URL with token:
```bash
./get-openclaw-url.sh
```
Output: `https://10.0.2.162/?token=9e56f4da7659390a5791329ff3c542452f500219e2178e00`

### 2. connect-openclaw.sh
SSM port forwarding for local access:
```bash
./connect-openclaw.sh [local-port] [remote-port]
```
Example: `./connect-openclaw.sh 18789 18789`

### 3. test-openclaw-connectivity.sh
Tests connectivity to openclaw from within VPC:
```bash
./test-openclaw-connectivity.sh
```

---

## Documentation Files

1. **SSM_ACCESS.md** - Complete access documentation
2. **SETUP_SUMMARY.md** - This file
3. **openclaw.md** (on server) - Original documentation

---

## Services Status

### openclaw.service
- **Status**: active (running)
- **Enabled**: Yes
- **Main Process**: openclaw-gateway
- **Config**: /home/ssm-user/.openclaw/openclaw.json
- **User**: ssm-user
- **Working Directory**: /home/ssm-user

### nginx.service
- **Status**: active (running)
- **Enabled**: Yes
- **Config Files**:
  - /etc/nginx/nginx.conf
  - /etc/nginx/conf.d/openclaw.conf
  - /etc/nginx/conf.d/openclaw-https.conf

---

## Verification

### Test HTTPS Access
```bash
curl -k -s -H "Authorization: Bearer 9e56f4da7659390a5791329ff3c542452f500219e2178e00" \
  https://10.0.2.162/ | head -5
```

Expected: HTML content from OpenClaw Control UI

### Test Port Listening
```bash
aws ssm start-session --region ap-southeast-2 --target i-0f6dac37c87940ba9
ss -tlnp | grep -E '(443|18789|3978|80)'
```

Expected: All ports listening on appropriate interfaces

### Test Device Pairing
```bash
aws ssm start-session --region ap-southeast-2 --target i-0f6dac37c87940ba9
openclaw devices list
```

Expected: 3 paired devices, 0 pending

---

## Troubleshooting

### If Control UI shows "origin not allowed"
Check allowed origins:
```bash
aws ssm start-session --region ap-southeast-2 --target i-0f6dac37c87940ba9
jq .gateway.controlUi.allowedOrigins ~/.openclaw/openclaw.json
```

### If Control UI shows "pairing required"
List and approve pending devices:
```bash
openclaw devices list
openclaw devices approve <request-id>
```

### If nginx returns 502 Bad Gateway
Check openclaw service:
```bash
systemctl status openclaw
ss -tlnp | grep 18789
```

### View OpenClaw Logs
```bash
journalctl -u openclaw -n 50 --no-pager
```

---

## Security Notes

1. **VPC-only Access**: Control UI and API are NOT exposed via the public ALB
2. **Self-signed Certificate**: Browser will show security warning - this is expected
3. **Token Authentication**: Gateway token required for all API and Control UI access
4. **Device Pairing**: Each browser/device must be paired and approved
5. **Trusted Proxies**: Only localhost (nginx) is trusted as a proxy

---

## Future Maintenance

### Certificate Renewal (after 365 days)
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/openclaw.key \
  -out /etc/nginx/ssl/openclaw.crt \
  -subj "/C=AU/ST=NSW/L=Sydney/O=DAME/CN=10.0.2.162" \
  -addext "subjectAltName=IP:10.0.2.162"
systemctl reload nginx
```

### Rotate Gateway Token
```bash
# Generate new token (48 hex characters)
NEW_TOKEN=$(openssl rand -hex 24)
echo $NEW_TOKEN

# Update config
cd ~/.openclaw
jq --arg token "$NEW_TOKEN" '.gateway.auth.token = $token' openclaw.json > openclaw.json.new
mv openclaw.json.new openclaw.json
systemctl restart openclaw

# Update get-openclaw-url.sh with new token
```

### Add New Allowed Origin
```bash
cd ~/.openclaw
jq '.gateway.controlUi.allowedOrigins += ["https://new-origin"]' openclaw.json > openclaw.json.new
mv openclaw.json.new openclaw.json
systemctl restart openclaw
```

---

## Configuration Files Backup

All configuration backups are stored in:
- `/home/ssm-user/.openclaw/openclaw.json.bak.*`

To restore a backup:
```bash
cd ~/.openclaw
cp openclaw.json.bak.https openclaw.json
systemctl restart openclaw
```
