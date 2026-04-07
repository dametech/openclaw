# Jira Reference

## Credentials

Credentials are stored per-user at `~/.openclaw/.jira-credentials/<loginKey>.json`:

```json
{
  "baseUrl": "https://<org>.atlassian.net",
  "email": "user@example.com",
  "apiToken": "..."
}
```

For DAME: loginKey is `<your-jira-login-key>`, baseUrl is `https://<your-jira-domain>`.

Load with:
```python
import json, os
with open(os.path.expanduser("~/.openclaw/.jira-credentials/<your-jira-login-key>.json")) as f:
    creds = json.load(f)
```

## jira_query Tool

Use `jira_query` for reads and simple operations. Always pass `loginKey: "<your-jira-login-key>"`.

| Action | Use for |
|--------|---------|
| `my_open_tickets` | List open tickets assigned to current user |
| `search_jql` | Search with JQL |
| `issue_get` | Fetch issue fields + comments |
| `issue_create` | Create new issue |
| `issue_update` | Update fields |
| `issue_transition` | Change status |
| `comment_add` | Simple one-liner comments only |

## ADF Comments (always use for rich content)

**Never use `jira_query comment_add` for formatted content** — it posts plain text that Jira converts into a wall of separate paragraphs.

Instead, use `scripts/adf.py` with the `JiraClient`:

```python
import sys
sys.path.insert(0, "<skill-dir>/scripts")
from adf import JiraClient, heading, p, pb, bullet, ordered, code_block, panel, rule
import json, os

with open(os.path.expanduser("~/.openclaw/.jira-credentials/<your-jira-login-key>.json")) as f:
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

## Common JQL Patterns

```
# My overdue open tickets
assignee = currentUser() AND duedate <= now() AND statusCategory != Done ORDER BY duedate ASC

# Recently updated tickets in a project
project = AU04 AND updated >= -7d ORDER BY updated DESC

# Tickets blocked or in progress
assignee = currentUser() AND status in ("In Progress", "Blocked") ORDER BY priority DESC

# Search by text
text ~ "sensor" AND text ~ "design decision" ORDER BY updated DESC
```

## Issue Transitions

Common transition names (case-insensitive):
- `"In Progress"` — start work
- `"Done"` — complete
- `"Blocked"` — mark as blocked
- `"To Do"` — reopen

Use `jira_query` with `action: "issue_transition"` and `transitionName`.
