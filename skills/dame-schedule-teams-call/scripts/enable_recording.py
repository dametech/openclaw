#!/usr/bin/env python3"""
enable_recording.py - Find a Teams online meeting by joinWebUrl and enable auto-recording.

Usage:
  ACCESS_TOKEN=<token> python3 enable_recording.py <joinWebUrl>

The joinWebUrl should be taken from the event response's onlineMeeting.joinUrl field.
The access token is read from the ACCESS_TOKEN environment variable (not a CLI arg).
"""
import sys
import os
import json
import requests

def main():
    if len(sys.argv) != 2:
        print("Usage: ACCESS_TOKEN=<token> enable_recording.py <joinWebUrl>", file=sys.stderr)
        sys.exit(1)

    join_url = sys.argv[1]
    access_token = os.environ.get("ACCESS_TOKEN")
    if not access_token:
        print("Error: ACCESS_TOKEN environment variable is not set.", file=sys.stderr)
        sys.exit(1)

    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
    }

    # Step 1: Find the online meeting by joinWebUrl
    resp = requests.get(
        "https://graph.microsoft.com/v1.0/me/onlineMeetings",
        params={"$filter": f"joinWebUrl eq '{join_url}'"},
        headers=headers
    )
    resp.raise_for_status()
    data = resp.json()

    if not data.get('value'):
        print("ERROR: No meeting found for that joinWebUrl")
        sys.exit(1)

    meeting = data['value'][0]
    meeting_id = meeting['id']
    print(f"Found meeting: {meeting.get('subject')}")
    print(f"recordAutomatically (before): {meeting.get('recordAutomatically')}")

    # Step 2: PATCH to enable auto-recording
    resp2 = requests.patch(
        f"https://graph.microsoft.com/v1.0/me/onlineMeetings/{meeting_id}",
        json={"recordAutomatically": True},
        headers=headers
    )
    resp2.raise_for_status()
    result = resp2.json()

    print(f"recordAutomatically (after): {result.get('recordAutomatically')}")
    if result.get('recordAutomatically'):
        print("✅ Auto-recording enabled successfully")
    else:
        print("❌ WARNING: recordAutomatically still False after PATCH")
        sys.exit(1)

if __name__ == '__main__':
    main()
