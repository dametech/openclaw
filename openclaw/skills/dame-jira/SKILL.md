---
name: dame-jira
description: Post rich formatted comments to DAME Jira using ADF. Use when a Jira comment needs headings, panels, lists, code blocks, quotes, or other structured formatting beyond a plain text one-liner.
---

# DAME Jira Skill

Read the full reference at `references/jira.md`.

This skill is only for rich formatted Jira comments.

Do not use this skill for:
- basic Jira reads
- ticket creation or updates
- transitions
- plain one-line comments

For those, use the `jira_query` plugin directly.

## Prerequisite

Before using `scripts/adf.py`, make sure pod-local Jira credentials exist at:

```text
~/.openclaw/jira-credentials.json
```

If they do not exist, configure them with `jira_query action="login_setup"`.

## Rule

For rich comments, always use `scripts/adf.py` via Python. Do not use `jira_query comment_add` for anything beyond a plain one-liner.

## Posting A Formatted Comment

```python
import sys, json, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../scripts"))
from adf import JiraClient, heading, p, pb, bullet, ordered, code_block, panel, rule

with open(os.path.expanduser("~/.openclaw/jira-credentials.json")) as f:
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

The skill directory is this repo path: `openclaw/skills/dame-jira`

## Key Rules

- DAME base URL is `https://dame-technologies.atlassian.net`
- Credentials come from `~/.openclaw/jira-credentials.json`
- Rich comments must use `scripts/adf.py`
- See `references/jira.md` for credential setup and ADF node reference
