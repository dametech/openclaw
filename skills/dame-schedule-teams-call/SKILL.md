---
name: dame-schedule-teams-call
description: Schedule a Microsoft Teams meeting using the DAME Scrummaster account on behalf of any user. Use when anyone asks to schedule, book, or create a Teams meeting or call. The meeting is always organised by the Scrummaster account (not the requester's account), with auto-recording and transcription enabled by default. Triggers on phrases like "schedule a Teams call", "book a meeting", "set up a Teams meeting", "create a call with [people]", etc.
---

# DAME Schedule Teams Call

Schedule Teams meetings via the Scrummaster account with auto-recording and transcription on.

## Required Info

Collect before proceeding (ask if not provided):
- **Title** — meeting subject
- **Attendees** — names or email addresses
- **Date & time** — always confirm timezone; convert to UTC for API calls (DAME is AEDT/UTC+11)
- **Duration** — default 30 minutes if not specified
- **Requester name + email** — who asked for the meeting; they are always added as an attendee automatically
- **Description** (optional) — agenda or context

## Workflow

Always use `authMode: "delegated"`, `loginKey: "srumm4st3r"` for every API call.

### Step 1: Resolve attendee emails

If given names instead of emails, look up via MS Graph:
```
GET /v1.0/users?$filter=displayName eq '{name}'&$select=displayName,mail,userPrincipalName
```
Or search:
```
GET /v1.0/users?$search="displayName:{name}"&$select=displayName,mail,userPrincipalName
```
(Add header: `ConsistencyLevel: eventual` for search queries)

### Step 2: Create the calendar event

```
POST /v1.0/me/events
```

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
python3 <skill_dir>/scripts/enable_recording.py "<joinUrl from Step 2>" "<srumm4st3r_access_token>"
```

To get the access token, read it from `/home/ssm-user/.openclaw/ms-graph-query-tokens.json`:
```python
import json
token = json.load(open('/home/ssm-user/.openclaw/ms-graph-query-tokens.json'))['delegated']['srumm4st3r']['access_token']
```

The script will print `✅ Auto-recording enabled successfully` on success. If it fails, do not proceed — recording will not work.

Alternatively, if doing it manually via ms_graph_query:
1. `GET /v1.0/me/onlineMeetings?$filter=joinWebUrl eq '<joinUrl>'` — do NOT add `$select`
2. Take the `id` from `value[0].id` **exactly as returned** (do not re-encode or modify it)
3. `PATCH /v1.0/me/onlineMeetings/<id>` with `{"recordAutomatically": true}`

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
- **Do NOT pass `onlineMeetingUrl` in the events body** — it is ignored by the API and a new meeting is always created
- For recurring meetings, use the `recurrence` field in the events API
- If attendee lookup fails, ask the requester to provide the email directly
