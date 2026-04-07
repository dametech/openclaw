---
name: jira
description: Read and write Jira issues, post rich formatted comments, search with JQL, manage transitions, and work with attachments. Use when creating or updating Jira tickets, posting formatted comments with code blocks/panels/lists, searching for issues, transitioning issue status, or fetching issue details. Triggers on phrases like "post to the ticket", "add a comment on Jira", "create a Jira ticket", "update the ticket", "transition to done", "search Jira for", "what tickets are overdue", etc.
---

# Jira Skill

Read the full reference at `references/jira.md`.

## Quick Start

**For reads and simple writes:** use the `jira_query` tool with `loginKey: "<your-agent-id>"`.

**For formatted comments:** always use `scripts/adf.py` via Python — never use `jira_query comment_add` for anything beyond a plain one-liner.

## Posting a Formatted Comment

```python
import sys, json, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../scripts"))
from adf import JiraClient, heading, p, pb, bullet, ordered, code_block, panel, rule

with open(os.path.expanduser("~/.openclaw/.jira-credentials/<your-agent-id>.json")) as f:
    creds = json.load(f)

jira = JiraClient(creds["baseUrl"], creds["email"], creds["apiToken"])
jira.add_comment("PROJ-123", [
    heading("Title", 2),
    panel("Important note", "info"),
    pb("Steps:"),
    ordered(["Step 1", "Step 2"]),
    code_block("command here", "bash"),
])
```

The skill directory is at: `/home/ssm-user/.openclaw/workspace-<your-agent-id>/skills/jira`

## Key Rules

- Always pass `loginKey: "<your-agent-id>"` to `jira_query`
- Rich comments → `scripts/adf.py` (renders properly in Jira UI)
- Plain one-liners → `jira_query comment_add` is acceptable
- See `references/jira.md` for credentials, JQL patterns, ADF node reference, and transition names
