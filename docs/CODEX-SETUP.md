# OpenAI Codex CLI Setup

## Overview

[OpenAI Codex CLI](https://github.com/openai/codex) is an AI-powered coding assistant that runs in the terminal. It can write code, run commands, and work with your codebase.

Codex is not installed by default on OpenClaw pods. Use this guide only if you want to install and configure it separately.

## Authentication

Codex requires an OpenAI API key. Two options:

### Option 1: Environment Variable (recommended for agents)

Set `OPENAI_API_KEY` in the container environment via K8s Secret:

```bash
# Create the secret (or add to existing)
kubectl create secret generic openclaw-openai \
  --namespace openclaw \
  --from-literal=OPENAI_API_KEY='sk-...'

# Add to Helm values envFrom
```

Or store the key in 1Password and inject at runtime:

```bash
export OPENAI_API_KEY=$(op item get "OpenAI API Key" --vault Infrastructure --fields credential)
codex exec "explain this codebase"
```

### Option 2: Codex Login (interactive, per-user)

```bash
# Login with API key from stdin
echo "$OPENAI_API_KEY" | codex login --with-api-key

# Or device auth (opens browser - not suitable for headless)
codex login --device-auth

# Check status
codex login status
```

Credentials stored at `~/.codex/config.toml`.

## 1Password Integration

Add an OpenAI API key item to the `Infrastructure` vault:

| Item Name | Type | Fields |
|-----------|------|--------|
| `OpenAI API Key` | API Credential | `credential` (the sk-... key) |

Then agents can fetch it on-demand:

```bash
OPENAI_API_KEY=$(op item get "OpenAI API Key" --vault Infrastructure --fields credential) \
  codex exec "write a test for this function"
```

## Usage Examples

```bash
# Non-interactive (agent-friendly)
codex exec "explain the architecture of this project"
codex exec "write unit tests for src/main.py"
codex exec "find and fix the bug in handler.go"

# Code review
codex review

# Interactive session
codex "refactor this module"
```

## Model Configuration

Default model is `gpt-5.3-codex`. Override with config:

```bash
codex -c model="gpt-5.4" exec "your prompt"
```

## Action Required

- [ ] Add OpenAI API key to 1Password `Infrastructure` vault
- [ ] Either inject as `OPENAI_API_KEY` env var or have agents fetch from 1Password per-invocation
