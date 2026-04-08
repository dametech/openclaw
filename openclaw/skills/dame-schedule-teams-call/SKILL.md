---
name: dame-schedule-teams-call
description: Schedule a Microsoft Teams meeting using the DAME Scrummaster account on behalf of any user. Use when anyone asks to schedule, book, or create a Teams meeting or call. The meeting is always organised by the Scrummaster account (not the requester's account), with auto-recording and transcription enabled by default. Triggers on phrases like "schedule a Teams call", "book a meeting", "set up a Teams meeting", "create a call with [people]", etc.
---

# DAME Schedule Teams Call

Schedule Teams meetings via the Scrummaster account with auto-recording and transcription on.

This skill is split by pod role:
- On non-Scrummaster pods: delegate the full scheduling request to the Scrummaster pod `oc-sm`
- On the Scrummaster pod `oc-sm`: perform the scheduling flow locally

## Pod Routing

Before doing any Microsoft Graph or calendar work, determine whether you are already on the Scrummaster pod.

Use a quick shell check such as:

```bash
hostname
```

Rules:
- If the current pod is `oc-sm` (or its hostname/deployment clearly belongs to the `oc-sm` release), continue with the local scheduling workflow below
- If the current pod is not `oc-sm`, do not schedule locally. Delegate the request to target `oc-sm` with the `pod_delegate` plugin and wait for the result

### Delegation From Non-Scrummaster Pods

Use `pod_delegate`:
- `action="delegate_start"`
- `target="oc-sm"`
- `message` should clearly state that `oc-sm` must execute the `dame-schedule-teams-call` skill and include all collected meeting details

The delegated payload must include:
- title
- attendees
- date and time
- timezone
- duration
- requester name
- requester email
- optional description or agenda

After starting the job:
1. Check with `delegate_status`
2. Fetch the final reply with `delegate_result`
3. Return the Scrummaster pod's final scheduling result to the user

If delegation to `oc-sm` is unavailable or fails, say so explicitly instead of attempting to schedule from the wrong pod

## Required Info

Collect before proceeding (ask if not provided):
- **Title** — meeting subject
- **Attendees** — names or email addresses
- **Date & time** — always confirm timezone; convert to UTC for API calls (DAME is AEDT/UTC+11)
- **Duration** — default 30 minutes if not specified
- **Requester name + email** — who asked for the meeting; they are always added as an attendee automatically
- **Description** (optional) — agenda or context

## Workflow

Only the `oc-sm` pod should execute the workflow below.

Use the `ms_graph_query` plugin with:
- `action="query"` for Graph API calls
- delegated device-code login for authentication

There is no `loginKey` parameter anymore.

Before scheduling, confirm authentication:
1. Run `ms_graph_query` with `action="login_status"`
2. If not authenticated, run `action="login_start"`
3. Complete the device-code login
4. Run `action="login_poll"` until authentication succeeds

The plugin stores a single delegated token in `~/.openclaw/ms-graph-query-tokens.json`.

### Step 1: Resolve attendee emails

If given names instead of emails, resolve them through a `/v1.0/me...` path that the current plugin allowlist supports.

Preferred lookup:
```
GET /v1.0/me/people?$search="{name}"
```

Use `ms_graph_query` with:
- `action="query"`
- `method="GET"`
- `path="/v1.0/me/people?$search={name}"`

Then extract the best available email from returned fields such as `scoredEmailAddresses`.

If the lookup does not return a clear email address, ask the requester to provide the attendee email directly. Do not rely on the old `/v1.0/users` lookup.

### Step 2: Create the calendar event

Use `ms_graph_query` with:
- `action="query"`
- `method="POST"`
- `path="/v1.0/me/events"`
- `body=<event payload>`

Body:
```json
{
  "subject": "<meeting title>",
  "body": {
    "contentType": "HTML",
    "content": "<p><em>This call was scheduled by Scrummaster on behalf of <strong>[Requester Name]</strong>.</em></p><p>[Optional agenda/description]</p>"
  },
  "start": { "dateTime": "<ISO8601 UTC>", "timeZone": "UTC" },
  "end":   { "dateTime": "<ISO8601 UTC>", "timeZone": "UTC" },
  "isOnlineMeeting": true,
  "onlineMeetingProvider": "teamsForBusiness",
  "attendees": [
    { "emailAddress": { "address": "<requester_email>", "name": "<requester_name>" }, "type": "required" },
    { "emailAddress": { "address": "<other_attendee_email>", "name": "<name>" }, "type": "required" }
  ]
}
```

From the response, capture `onlineMeeting.joinUrl`.

### Step 3: Enable auto-recording ⚠️ MANDATORY — do not skip

**This step is required. The calendar event API always creates a new Teams meeting with recording OFF by default. Without this step, the meeting will NOT auto-record.**

Use the bundled script to avoid meeting ID encoding issues (copy-pasting the ID manually causes subtle encoding errors):

```bash
ACCESS_TOKEN="$(python3 - <<'PY'
import json
import os
store = json.load(open(os.path.expanduser("~/.openclaw/ms-graph-query-tokens.json")))
print(store["delegated"]["access_token"])
PY
)" python3 <skill_dir>/scripts/enable_recording.py "<joinUrl from Step 2>"
```

The token is passed via environment variable, not as a CLI argument.

The script will print `✅ Auto-recording enabled successfully` on success. If it fails, do not proceed — recording will not work.

Alternatively, if doing it manually via ms_graph_query:
1. Run `ms_graph_query` with `action="query"`, `method="GET"`, `path="/v1.0/me/onlineMeetings?$filter=joinWebUrl eq '<joinUrl>'"` — do not add `$select`
2. Take the `id` from `value[0].id` **exactly as returned** (do not re-encode or modify it)
3. Run `ms_graph_query` with `action="query"`, `method="PATCH"`, `path="/v1.0/me/onlineMeetings/<id>"`, `body={"recordAutomatically": true}`

### Step 4: Confirm to the user

Reply with:
- ✅ Meeting title and time (in requester's local timezone)
- 👥 Attendees
- 🔗 Join URL (`joinUrl` from Step 2)
- 🎙️ Recording & transcript: auto-enabled
- 📅 Invite sent to all attendees

## Notes

- **All meetings use `scrumm4st3r@dame.energy`** as organiser — never the requester's account
- **The requester is always added as a `required` attendee** — even if they don't list themselves
- The invite body attribution format is: *"This call was scheduled by Scrummaster on behalf of **[Name]**."*
- The current `ms_graph_query` plugin uses one delegated token store and does not support `loginKey`
- **Do NOT pass `onlineMeetingUrl` in the events body** — it is ignored by the API and a new meeting is always created
- For recurring meetings, use the `recurrence` field in the events API
- If attendee lookup fails, ask the requester to provide the email directly
