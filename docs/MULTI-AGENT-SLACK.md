# Multi-Agent Slack Configuration

This guide explains how to configure multiple OpenClaw agents with different names and personalities using a **single Slack app**.

## Two Approaches

### Approach 1: Single Slack App, Multiple Agents (Recommended)

Use **one** Slack app, but configure multiple agents with different identities in `openclaw.json`. All agents share the same bot token but can have unique names and personalities.

**Pros:**
- Simple setup - only one Slack app to manage
- Single set of OAuth scopes
- All agents accessible through one bot
- Easy to add/remove agents

**Cons:**
- All agents show as the same Slack app in the sidebar
- Shares rate limits across all agents

### Approach 2: Multiple Slack Apps, Separate Agents

Create **separate** Slack apps for each persona (e.g., "Dave from DevOps", "Sarah from Sales"). Each has its own tokens and shows as a different bot in Slack.

**Pros:**
- Each agent is a distinct Slack bot
- Separate rate limits per bot
- Clear visual separation in Slack

**Cons:**
- Requires creating multiple Slack apps
- More OAuth scopes to manage
- More complex configuration

## Configuration Examples

### Single App, Multiple Agents (Recommended)

#### Step 1: Configure Agents in openclaw.json

```json5
{
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "appToken": "${SLACK_APP_TOKEN}",
      "botToken": "${SLACK_BOT_TOKEN}",
      "userAuth": {
        "mode": "allowlist"
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace",
      "model": {
        "primary": "anthropic/claude-opus-4-6"
      }
    },
    "list": [
      {
        "id": "dave-devops",
        "identity": {
          "name": "Dave from DevOps",
          "emoji": "🔧",
          "systemPrompt": "You are Dave, a helpful DevOps engineer. You specialize in infrastructure, CI/CD, and Kubernetes."
        },
        "workspace": "/home/node/.openclaw/workspace/dave",
        "bindings": {
          "slack": {
            "channels": ["C01DEVOPS123"],  // Specific DevOps channel
            "keywords": ["deploy", "kubernetes", "ci/cd", "pipeline"]
          }
        }
      },
      {
        "id": "sarah-sales",
        "identity": {
          "name": "Sarah from Sales",
          "emoji": "💼",
          "systemPrompt": "You are Sarah, a sales operations specialist. You help with CRM, deal tracking, and sales analytics."
        },
        "workspace": "/home/node/.openclaw/workspace/sarah",
        "bindings": {
          "slack": {
            "channels": ["C02SALES456"],  // Specific Sales channel
            "keywords": ["deal", "crm", "salesforce", "quote"]
          }
        }
      },
      {
        "id": "alex-support",
        "identity": {
          "name": "Alex from Support",
          "emoji": "🎧",
          "systemPrompt": "You are Alex, a customer support specialist. You help troubleshoot issues and answer customer questions."
        },
        "workspace": "/home/node/.openclaw/workspace/alex",
        "bindings": {
          "slack": {
            "channels": ["C03SUPPORT789"],  // Specific Support channel
            "keywords": ["ticket", "customer", "issue", "help"]
          }
        },
        "default": true  // Handles messages when no other agent matches
      }
    ]
  }
}
```

#### Step 2: Enable Custom Bot Identity

To show different names in Slack, enable the `chat:write.customize` scope (should already be in the setup script).

With this scope, each agent's messages will show their custom name and emoji.

### How Agent Routing Works

OpenClaw routes messages to agents based on:

1. **Channel Bindings**: Messages from specific channels go to designated agents
2. **Keyword Matching**: Messages containing keywords route to matching agents
3. **Direct Assignment**: You can route by Slack user ID or thread
4. **Default Agent**: Handles messages when no specific routing matches

#### Example Message Flow

```
User in #devops: "Can you deploy the API to production?"
  → Matches "dave-devops" (channel: C01DEVOPS123, keyword: "deploy")
  → Response from "Dave from DevOps 🔧"

User in #sales: "What's the status of the Acme deal?"
  → Matches "sarah-sales" (channel: C02SALES456, keyword: "deal")
  → Response from "Sarah from Sales 💼"

User in #general: "I need help with my laptop"
  → No specific match
  → Routes to "alex-support" (default agent)
  → Response from "Alex from Support 🎧"
```

### Advanced Routing Configuration

#### Route by User

```json5
{
  "id": "exec-assistant",
  "identity": {
    "name": "Executive Assistant",
    "emoji": "👔"
  },
  "bindings": {
    "slack": {
      "users": ["U01CEO123", "U02CFO456"]  // Only responds to these users
    }
  }
}
```

#### Route by Thread

```json5
{
  "id": "incident-manager",
  "identity": {
    "name": "Incident Commander",
    "emoji": "🚨"
  },
  "bindings": {
    "slack": {
      "keywords": ["incident", "p0", "outage"],
      "requireMention": true  // Must be mentioned in thread
    }
  }
}
```

#### Time-Based Routing

```json5
{
  "id": "after-hours",
  "identity": {
    "name": "On-Call Bot",
    "emoji": "🌙"
  },
  "bindings": {
    "slack": {
      "schedule": {
        "timezone": "America/New_York",
        "hours": "18:00-08:00",  // 6 PM to 8 AM
        "days": ["Sat", "Sun"]     // Plus weekends
      }
    }
  }
}
```

## Multiple Slack Apps (Alternative)

If you need completely separate Slack bots, create multiple apps and configure accounts:

```json5
{
  "channels": {
    "slack": {
      "enabled": true,
      "accounts": {
        "dave-devops": {
          "mode": "socket",
          "appToken": "${SLACK_DAVE_APP_TOKEN}",
          "botToken": "${SLACK_DAVE_BOT_TOKEN}",
          "agent": "dave-devops"
        },
        "sarah-sales": {
          "mode": "socket",
          "appToken": "${SLACK_SARAH_APP_TOKEN}",
          "botToken": "${SLACK_SARAH_BOT_TOKEN}",
          "agent": "sarah-sales"
        }
      }
    }
  },
  "agents": {
    "list": [
      {
        "id": "dave-devops",
        "identity": {
          "name": "Dave from DevOps",
          "emoji": "🔧"
        }
      },
      {
        "id": "sarah-sales",
        "identity": {
          "name": "Sarah from Sales",
          "emoji": "💼"
        }
      }
    ]
  }
}
```

This approach requires:
1. Creating separate Slack apps for each bot
2. Storing multiple sets of tokens in 1Password
3. Configuring separate Kubernetes secrets

## Kubernetes Deployment

### Single App Deployment

Use the existing `setup-slack-integration.sh` script, then update the ConfigMap:

```bash
kubectl edit configmap openclaw -n openclaw
```

Add the multi-agent configuration from the examples above.

Restart the deployment:

```bash
kubectl rollout restart deployment/openclaw -n openclaw
```

### Multiple Apps Deployment

Create separate secrets for each bot:

```bash
# Dave's tokens
kubectl create secret generic openclaw-slack-dave \
  --from-literal=SLACK_APP_TOKEN=$DAVE_APP_TOKEN \
  --from-literal=SLACK_BOT_TOKEN=$DAVE_BOT_TOKEN \
  -n openclaw

# Sarah's tokens
kubectl create secret generic openclaw-slack-sarah \
  --from-literal=SLACK_APP_TOKEN=$SARAH_APP_TOKEN \
  --from-literal=SLACK_BOT_TOKEN=$SARAH_BOT_TOKEN \
  -n openclaw
```

Update Helm values to reference all secrets:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          envFrom:
            - secretRef:
                name: openclaw-env-secret
            - secretRef:
                name: openclaw-slack-dave
                prefix: SLACK_DAVE_
            - secretRef:
                name: openclaw-slack-sarah
                prefix: SLACK_SARAH_
```

## Testing Multi-Agent Setup

### Test Agent Routing

1. **Test channel routing**:
   ```
   #devops: "Hey, can you help deploy something?"
   → Should get response from Dave
   ```

2. **Test keyword routing**:
   ```
   #general: "I need help with a Salesforce deal"
   → Should route to Sarah based on keywords
   ```

3. **Test default routing**:
   ```
   #random: "Hello!"
   → Should route to default agent (Alex)
   ```

### View Agent Activity

```bash
# Check logs for agent routing
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main -f | grep "agent"

# List active agents
kubectl exec -n openclaw deployment/openclaw -c main -- \
  node dist/index.js agents list
```

### Debug Routing Issues

If messages aren't routing correctly:

1. Check agent configuration:
   ```bash
   kubectl exec -n openclaw deployment/openclaw -c main -- \
     cat /home/node/.openclaw/openclaw.json | grep -A20 agents
   ```

2. Verify channel IDs match:
   ```bash
   # Get channel ID from Slack
   # Right-click channel → View channel details → Copy ID
   ```

3. Test keyword matching:
   ```bash
   # Check logs for routing decisions
   kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main | grep routing
   ```

## Best Practices

### Agent Design

1. **Clear Personas**: Give each agent a distinct role and expertise
2. **Non-Overlapping Keywords**: Avoid keyword conflicts between agents
3. **Default Agent**: Always configure a default to handle unmatched messages
4. **Workspace Isolation**: Give each agent their own workspace directory

### Channel Strategy

1. **Dedicated Channels**: Create channels for specific agent domains (#devops, #sales)
2. **Shared Channels**: Use keyword routing in general channels
3. **Private Channels**: Invite only relevant bots to private channels

### Scalability

1. **Start Small**: Begin with 2-3 agents, add more as needed
2. **Monitor Performance**: Watch for routing delays with many agents
3. **Resource Limits**: Adjust CPU/memory if running many concurrent agents

### Security

1. **User Allowlists**: Configure per-agent allowlists if needed
2. **Channel Restrictions**: Limit agents to specific channels
3. **Audit Logs**: Monitor which agents handle sensitive information

## Troubleshooting

### Agent Not Responding

**Problem**: Messages don't route to expected agent

**Solutions**:
- Verify channel ID matches configuration
- Check if keywords are specific enough
- Ensure agent is enabled
- Check logs for routing decisions

### Wrong Agent Responding

**Problem**: Messages route to incorrect agent

**Solutions**:
- Review keyword overlap between agents
- Make bindings more specific
- Adjust routing priority
- Use explicit channel bindings instead of keywords

### Agent Identity Not Showing

**Problem**: All messages show same bot name

**Solutions**:
- Verify `chat:write.customize` scope is added
- Check that agent `identity` is configured
- Ensure `name` and `emoji` are set correctly
- Restart gateway after configuration changes

## Examples Repository

See the `examples/multi-agent-slack/` directory for:
- Complete configuration templates
- Sample agent personas
- Routing scenarios
- Testing scripts

---

**Last Updated**: March 2026
**OpenClaw Version**: 2026.3.13+
