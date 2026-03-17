"""
ADF helper library for posting rich Jira comments via the REST API.

Usage:
    from adf import JiraClient, p, pb, heading, bullet, ordered, code_block, panel, rule

    jira = JiraClient(base_url, email, api_token)
    jira.add_comment("PROJ-123", [
        heading("My heading", 2),
        p("Some text"),
        code_block("sudo apt update", "bash"),
    ])
"""

import json
import base64
import urllib.request
import urllib.error


class JiraClient:
    def __init__(self, base_url: str, email: str, api_token: str):
        self.base_url = base_url.rstrip("/")
        self._auth = base64.b64encode(f"{email}:{api_token}".encode()).decode()

    def _request(self, method, path, body=None):
        url = f"{self.base_url}{path}"
        data = json.dumps(body).encode() if body else None
        req = urllib.request.Request(
            url, data=data,
            headers={
                "Authorization": f"Basic {self._auth}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            method=method,
        )
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())

    def add_comment(self, issue_key: str, content: list) -> dict:
        """Post an ADF-formatted comment to a Jira issue."""
        body = {"body": {"version": 1, "type": "doc", "content": content}}
        return self._request("POST", f"/rest/api/3/issue/{issue_key}/comment", body)

    def delete_comment(self, issue_key: str, comment_id: str) -> None:
        """Delete a comment by ID."""
        req = urllib.request.Request(
            f"{self.base_url}/rest/api/3/issue/{issue_key}/comment/{comment_id}",
            headers={"Authorization": f"Basic {self._auth}"},
            method="DELETE",
        )
        urllib.request.urlopen(req)

    def get_comments(self, issue_key: str) -> list:
        """Return list of comment dicts for an issue."""
        result = self._request("GET", f"/rest/api/3/issue/{issue_key}/comment")
        return result.get("comments", [])

    def get_issue(self, issue_key: str, fields=None) -> dict:
        """Return issue fields dict."""
        params = f"?fields={','.join(fields)}" if fields else ""
        return self._request("GET", f"/rest/api/3/issue/{issue_key}{params}")

    def update_issue(self, issue_key: str, fields: dict) -> None:
        """Update issue fields."""
        self._request("PUT", f"/rest/api/3/issue/{issue_key}", {"fields": fields})

    def transition_issue(self, issue_key: str, transition_name: str) -> None:
        """Transition an issue by transition name."""
        transitions = self._request("GET", f"/rest/api/3/issue/{issue_key}/transitions")
        for t in transitions.get("transitions", []):
            if t["name"].lower() == transition_name.lower():
                self._request("POST", f"/rest/api/3/issue/{issue_key}/transitions",
                               {"transition": {"id": t["id"]}})
                return
        raise ValueError(f"Transition '{transition_name}' not found")


# ── ADF node builders ──────────────────────────────────────────────────────────

def p(text: str) -> dict:
    """Plain paragraph."""
    return {"type": "paragraph", "content": [{"type": "text", "text": text}]}


def pb(text: str) -> dict:
    """Bold paragraph."""
    return {"type": "paragraph", "content": [
        {"type": "text", "text": text, "marks": [{"type": "strong"}]}
    ]}


def heading(text: str, level: int = 3) -> dict:
    return {"type": "heading", "attrs": {"level": level},
            "content": [{"type": "text", "text": text}]}


def bullet(items: list) -> dict:
    """Bulleted list. Each item is a string or an ADF node."""
    return {"type": "bulletList", "content": [
        {"type": "listItem", "content": [p(i) if isinstance(i, str) else i]}
        for i in items
    ]}


def ordered(items: list) -> dict:
    """Numbered list. Each item is a string or an ADF node."""
    return {"type": "orderedList", "content": [
        {"type": "listItem", "content": [p(i) if isinstance(i, str) else i]}
        for i in items
    ]}


def code_block(code: str, lang: str = "") -> dict:
    return {"type": "codeBlock", "attrs": {"language": lang},
            "content": [{"type": "text", "text": code}]}


def panel(text: str, panel_type: str = "info") -> dict:
    """panel_type: info | note | warning | error | success"""
    return {"type": "panel", "attrs": {"panelType": panel_type},
            "content": [p(text)]}


def rule() -> dict:
    return {"type": "rule"}


def blockquote(text: str) -> dict:
    return {"type": "blockquote", "content": [p(text)]}
