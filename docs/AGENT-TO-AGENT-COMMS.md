# Agent-to-Agent Communication

How agents communicate with each other in the DAME Software multi-agent setup. Documents the options evaluated, what we chose, and why.

## Options Evaluated

### 1. Slack Message API (sending as another bot)

**Approach:** Use the `message` tool with a different `accountId` to send messages via another agent's Slack bot.

**What happened:** Messages sent this way appear in the Slack DM as if the target agent said them — but they don't trigger the target agent's session. The message shows up in the human's DM with that bot, but the bot never processes it as an inbound message.

**Verdict:** ❌ Does not work for agent-to-agent communication. Only useful for sending notifications that appear to come from a specific bot.

### 2. `sessions_send` (built-in inter-session messaging)

**Approach:** Use OpenClaw's `sessions_send` tool to send a message directly into another agent's session.

**What happened:** Requires `tools.sessions.visibility: "all"` and `tools.agentToAgent.enabled: true` in `openclaw.json`. However, the visibility setting is evaluated at session start — changes don't take effect until the sending agent's session is reset. This makes it impractical for the admin agent (Claw) whose session has long-running context.

**Configuration required:**
```json5
{
  "tools": {
    "sessions": { "visibility": "all" },
    "agentToAgent": {
      "enabled": true,
      "allow": ["main", "davo", "siteconfig", "siteuis", "edgex", "minercode", "minermaint"]
    }
  }
}
```

**Features:**
- Ping-pong reply loop (configurable max turns)
- Reply-back with `REPLY_SKIP` to stop
- Announce step posts result to target channel
- Messages tagged with `provenance.kind = "inter_session"`

**Verdict:** ✅ Good for agent-initiated conversations in fresh sessions. ⚠️ Tricky when the sending agent's session predates the config change.

### 3. `openclaw agent` CLI (chosen approach)

**Approach:** Use the OpenClaw CLI command `openclaw agent --agent <id> --message "..." --deliver` to send a message to a specific agent and optionally deliver the reply to the agent's chat channel.

**What happened:** Works reliably. The CLI creates a new interaction with the target agent, the agent processes it (including tool use), and the reply is delivered to the agent's Slack DM with the human.

**Example:**
```bash
openclaw agent --agent davo \
  --message "Status check: are you blocked on anything?" \
  --deliver
```

**Features:**
- Synchronous — waits for the agent to complete and returns the reply
- `--deliver` flag sends the agent's reply to their chat channel
- Works regardless of the calling agent's session state
- Can be called from any agent via `exec`
- Agent processes the message with full tool access (can run commands, read files, etc.)

**Verdict:** ✅ **Chosen approach.** Most reliable, no session state dependencies, works from any context.

### 4. Chat Completions API

**Approach:** Enable OpenClaw's OpenAI-compatible chat completions endpoint and POST directly to each agent.

**What happened:** Not currently enabled on our deployment. Would require `gateway.api.completions` config and exposes an HTTP endpoint.

**Verdict:** ⏸️ Not evaluated further. Could be useful for external integrations but `openclaw agent` CLI covers our needs.

## Current Configuration

### openclaw.json settings

```json5
{
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["main", "davo", "siteconfig", "siteuis", "edgex", "minercode", "minermaint"]
    },
    "sessions": {
      "visibility": "all"
    }
  }
}
```

### How Claw (admin) communicates with agents

Primary method — CLI via exec:
```bash
openclaw agent --agent <agent-id> \
  --message "<message>" \
  --deliver
```

This is used for:
- Status check-ins (every 15 minutes for active agents)
- Notifying agents of configuration changes
- Assigning work or relaying instructions
- Getting confirmation of setup (e.g. GitHub access test)

### How agents could communicate with each other

If agents need to talk to each other (not just Claw → agent):
1. Use `sessions_send` tool (requires visibility config and fresh session)
2. Use `exec` to call `openclaw agent --agent <target> --message "..."`
3. Route through Claw as coordinator

Currently, all inter-agent communication goes through Claw as the coordinator. Direct agent-to-agent messaging is enabled in config but not actively used.

## Lessons Learned

1. **Session state matters:** `sessions_send` visibility is locked at session creation. Config changes need a session reset to take effect.
2. **CLI is the most reliable:** `openclaw agent` works regardless of session state, config timing, or calling context.
3. **`--deliver` is key:** Without it, the agent processes the message but the reply stays internal. With it, the reply goes to the agent's Slack channel.
4. **Slack bot identity ≠ message routing:** Sending a message via a bot's Slack account doesn't trigger that bot's agent session.

## TODO

- [ ] Consider using `sessions_send` for agent-to-agent once all agents have fresh sessions with correct visibility
- [ ] Evaluate Chat Completions API for external integrations
- [ ] Document patterns for agents requesting help from other agents (e.g. Mia asking Sanjay for an API endpoint)
- [ ] Consider a shared Slack channel where all agents can collaborate (with mention gating)
