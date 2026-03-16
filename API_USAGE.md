# OpenClaw API Usage Guide

## Overview

OpenClaw uses a **WebSocket-based Gateway API**, not a traditional REST API. The gateway provides agent chat completions, control methods, and system management.

## Access Information

**Gateway URL (HTTPS via nginx):**
```
https://10.0.2.162
```

**Gateway URL (HTTP direct):**
```
http://10.0.2.162:18789
```

**Authentication Token:**
```
9e56f4da7659390a5791329ff3c542452f500219e2178e00
```

---

## API Methods

### 1. Agent Chat Completions (CLI)

The primary way to interact with agents for chat completions.

**From the EC2 Instance:**
```bash
openclaw agent \
  --agent <agent-id> \
  --message "Your message here" \
  --json \
  --timeout 30
```

**Available Agents:**
- `4ndr3w`
- `srumm4st3r`
- `marc`
- `nick`
- `jack`
- `luc`
- `bradhodge`
- `l1z`
- `C4r0l1n3`
- `nicashlin`

**Example:**
```bash
openclaw agent \
  --agent 4ndr3w \
  --message "Hello, please summarize the current date and time" \
  --json
```

**Response Format:**
```json
{
  "runId": "920fd6ca-9627-4757-945b-b2081f60ce14",
  "status": "ok",
  "summary": "completed",
  "result": {
    "payloads": [
      {
        "text": "Hey! What's up?",
        "mediaUrl": null
      }
    ],
    "meta": {
      "durationMs": 12203,
      "agentMeta": {
        "sessionId": "013e4504-74d2-418f-b434-cc573be074ee",
        "provider": "amazon-bedrock",
        "model": "global.anthropic.claude-sonnet-4-6",
        "usage": {
          "input": 4,
          "output": 254,
          "cacheRead": 129632,
          "cacheWrite": 130102,
          "total": 130110
        }
      }
    }
  }
}
```

---

### 2. Gateway RPC Methods

Call gateway methods directly via the CLI.

**Health Check:**
```bash
openclaw gateway call health \
  --token 9e56f4da7659390a5791329ff3c542452f500219e2178e00 \
  --json
```

**Gateway Status:**
```bash
openclaw gateway call status \
  --token 9e56f4da7659390a5791329ff3c542452f500219e2178e00 \
  --json
```

**System Presence:**
```bash
openclaw gateway call system-presence \
  --token 9e56f4da7659390a5791329ff3c542452f500219e2178e00 \
  --json
```

**Cron Jobs:**
```bash
openclaw gateway call cron.list \
  --token 9e56f4da7659390a5791329ff3c542452f500219e2178e00 \
  --json
```

---

### 3. Control UI Access

Access the web-based Control UI with full agent management.

**URL (with authentication):**
```
https://10.0.2.162/?token=9e56f4da7659390a5791329ff3c542452f500219e2178e00
```

**Features:**
- Agent chat interface
- Session management
- Device pairing
- Configuration settings
- Real-time WebSocket connection

---

## Programmatic Access (From Your App)

### Option 1: SSH Tunnel + CLI Commands

**Set up SSH tunnel to EC2:**
```bash
# From your local machine
ssh -L 18789:127.0.0.1:18789 ec2-user@<bastion-or-ec2-with-access>
```

**Execute CLI commands:**
```bash
ssh ec2-user@<bastion> \
  "su - ssm-user -c 'openclaw agent --agent 4ndr3w --message \"Hello\" --json'"
```

### Option 2: WebSocket Client (Direct Integration)

OpenClaw uses WebSocket for real-time communication. You can build a WebSocket client in your application.

**WebSocket Connection URL:**
```
wss://10.0.2.162/
```

**Authentication:**
Include the token in the WebSocket connection parameters or initial handshake.

**Note:** WebSocket protocol details would need to be reverse-engineered from the Control UI JavaScript or documented by OpenClaw.

### Option 3: SSM Command Execution

Execute openclaw commands remotely via AWS SSM.

**Python Example:**
```python
import boto3
import json
import time

ssm = boto3.client('ssm', region_name='ap-southeast-2')

def openclaw_chat(agent_id, message):
    # Send command
    response = ssm.send_command(
        InstanceIds=['i-0f6dac37c87940ba9'],
        DocumentName='AWS-RunShellScript',
        Parameters={
            'commands': [
                f'su - ssm-user -c "openclaw agent --agent {agent_id} --message \\"{message}\\" --json"'
            ]
        }
    )

    command_id = response['Command']['CommandId']

    # Wait for completion
    time.sleep(15)

    # Get output
    output = ssm.get_command_invocation(
        CommandId=command_id,
        InstanceId='i-0f6dac37c87940ba9'
    )

    return json.loads(output['StandardOutputContent'])

# Usage
result = openclaw_chat('4ndr3w', 'Hello, please respond briefly')
print(result['result']['payloads'][0]['text'])
```

**Bash Example:**
```bash
#!/bin/bash

AGENT_ID="4ndr3w"
MESSAGE="Hello, this is a test"

COMMAND_ID=$(aws ssm send-command \
    --region ap-southeast-2 \
    --instance-ids i-0f6dac37c87940ba9 \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"su - ssm-user -c 'openclaw agent --agent $AGENT_ID --message \\\"$MESSAGE\\\" --json'\"]" \
    --query 'Command.CommandId' \
    --output text)

sleep 15

aws ssm get-command-invocation \
    --region ap-southeast-2 \
    --command-id "$COMMAND_ID" \
    --instance-id i-0f6dac37c87940ba9 \
    --query 'StandardOutputContent' \
    --output text
```

---

## Agent Configuration

Each agent has its own workspace and configuration:

**Agent Details (from openclaw.json):**
```json
{
  "id": "4ndr3w",
  "workspace": "/home/ssm-user/.openclaw/workspace-4ndr3w",
  "model": "amazon-bedrock/global.anthropic.claude-sonnet-4-6"
}
```

**Available Models:**
- `amazon-bedrock/global.anthropic.claude-sonnet-4-6` (primary)
- `amazon-bedrock/global.anthropic.claude-opus-4-6-v1`
- `amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0`
- `runpod-qwen35/Qwen/Qwen3.5-4B`

---

## Advanced Usage

### Session Management

**Create persistent session:**
```bash
openclaw agent \
  --session-id my-custom-session \
  --agent 4ndr3w \
  --message "Start of conversation"
```

**Continue session:**
```bash
openclaw agent \
  --session-id my-custom-session \
  --agent 4ndr3w \
  --message "Continue our previous conversation"
```

### Thinking Levels

Control the agent's reasoning depth:

```bash
openclaw agent \
  --agent 4ndr3w \
  --message "Complex problem to solve" \
  --thinking high
```

**Options:** `off`, `minimal`, `low`, `medium`, `high`

### Verbose Mode

Enable detailed logging for debugging:

```bash
openclaw agent \
  --agent 4ndr3w \
  --message "Debug this issue" \
  --verbose on
```

### Custom Timeout

Extend timeout for long-running tasks:

```bash
openclaw agent \
  --agent 4ndr3w \
  --message "Complex analysis task" \
  --timeout 300
```

---

## Error Handling

### Common Errors

**Gateway connection failed:**
- Check if openclaw service is running: `systemctl status openclaw`
- Check if port 18789 is listening: `ss -tlnp | grep 18789`

**Unauthorized:**
- Verify token: `jq .gateway.auth.token ~/.openclaw/openclaw.json`
- Check allowed origins: `jq .gateway.controlUi.allowedOrigins ~/.openclaw/openclaw.json`

**Agent not found:**
- List available agents: `jq '.agents.list[].id' ~/.openclaw/openclaw.json`

**Timeout:**
- Increase timeout: `--timeout 120`
- Check model provider connectivity
- Review logs: `journalctl -u openclaw -n 50`

---

## Rate Limiting & Costs

**Model Costs (per 1M tokens):**
- Sonnet 4.6: $3 input / $15 output
- Opus 4.6: $5 input / $25 output
- Haiku 4.5: $1 input / $5 output

**Cache Costs:**
- Cache read: 10% of input cost
- Cache write: 1.25x input cost

**Concurrency Limits:**
- Max concurrent agents: 6 (default)
- Max concurrent subagents: 8 (default)

---

## Monitoring

### Check Gateway Health

```bash
openclaw gateway call health --json
```

### View Active Sessions

```bash
# Connect to instance
aws ssm start-session --region ap-southeast-2 --target i-0f6dac37c87940ba9

# List session directories
ls -la ~/.openclaw/agents/*/sessions/
```

### Monitor Logs

```bash
# Real-time logs
journalctl -u openclaw -f

# Recent errors
journalctl -u openclaw -n 100 --no-pager | grep -i error

# Gateway file logs
tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log
```

---

## Security Best Practices

1. **Token Management:**
   - Store token in environment variables or secure vault
   - Rotate token periodically
   - Never commit token to version control

2. **Network Access:**
   - Access only from VPC (10.0.0.0/16)
   - Use VPN for remote access
   - HTTPS for all connections

3. **Device Pairing:**
   - Review pending devices regularly
   - Reject unknown pairing requests
   - Audit paired devices periodically

4. **Audit Logging:**
   - Monitor agent activity logs
   - Track API usage and costs
   - Review unauthorized access attempts

---

## Support & Documentation

**Official Documentation:**
https://docs.openclaw.ai

**CLI Help:**
```bash
openclaw --help
openclaw agent --help
openclaw gateway --help
```

**Gateway Status:**
```bash
openclaw gateway status
```

**Health Check:**
```bash
openclaw health
```

**Doctor (Diagnostics):**
```bash
openclaw doctor
```
