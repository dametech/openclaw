# Jira Reference

## Credentials

Credentials are stored at:

```text
~/.openclaw/jira-credentials.json
```

Shape:

```json
{
  "baseUrl": "https://<org>.atlassian.net",
  "email": "user@example.com",
  "apiToken": "...",
  "defaultProjectKeys": ["PROJ"]
}
```

For DAME, the base URL is `https://dame-technologies.atlassian.net`.

Set credentials with `jira_query action="login_setup"` using:
- `email`
- `apiToken`
- optional `defaultProjectKeys`

Load with:
```python
import json, os
with open(os.path.expanduser("~/.openclaw/jira-credentials.json")) as f:
    creds = json.load(f)
```

## ADF Comments (always use for rich content)

**Never use `jira_query comment_add` for formatted content** — it posts plain text that Jira converts into a wall of separate paragraphs.

Instead, use `scripts/adf.py` with the `JiraClient`:

```python
import sys
sys.path.insert(0, "<skill-dir>/scripts")
from adf import JiraClient, heading, p, pb, bullet, ordered, code_block, panel, rule
import json, os

with open(os.path.expanduser("~/.openclaw/jira-credentials.json")) as f:
    creds = json.load(f)

jira = JiraClient(creds["baseUrl"], creds["email"], creds["apiToken"])

jira.add_comment("PROJ-123", [
    heading("Summary", 2),
    panel("Recovery: use PiKVM if SSH is lost", "info"),
    pb("Steps:"),
    ordered([
        "First step",
        "Second step",
    ]),
    code_block("sudo netplan apply", "bash"),
])
```

## ADF Node Reference

| Function | Output |
|----------|--------|
| `p("text")` | Plain paragraph |
| `pb("text")` | Bold paragraph |
| `heading("text", level)` | Heading (level 1–6) |
| `bullet(["a", "b"])` | Bulleted list |
| `ordered(["a", "b"])` | Numbered list |
| `code_block("code", "bash")` | Code block with syntax highlighting |
| `panel("text", "info")` | Coloured panel (info/note/warning/error/success) |
| `rule()` | Horizontal divider |
| `blockquote("text")` | Block quote |
