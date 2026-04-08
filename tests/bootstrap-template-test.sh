#!/bin/bash

set -euo pipefail

BOOTSTRAP_FILE="openclaw/workspace/BOOTSTRAP.md"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$BOOTSTRAP_FILE"; then
        echo "missing expected pattern in $BOOTSTRAP_FILE: $pattern" >&2
        exit 1
    fi
}

if [ ! -f "$BOOTSTRAP_FILE" ]; then
    echo "missing expected file: $BOOTSTRAP_FILE" >&2
    exit 1
fi

assert_contains '## Microsoft Graph Login'
assert_contains '`ms_graph_query`'
assert_contains 'gateway tool'
assert_contains '`ms_graph_query` is expected to be available on this pod.'
assert_contains 'Do not ask the user whether `ms_graph_query` is expected to be available.'
assert_contains 'Invoke `ms_graph_query` directly as a tool call.'
assert_contains 'Do not use the `openclaw` CLI'
assert_contains 'Do not probe `/tools/invoke`, `/v1/responses`, other gateway endpoints, or Microsoft device-code endpoints directly'
assert_contains 'immediately call `ms_graph_query` with `action="login_start"` as the first step'
assert_contains 'Do not spend time discovering invocation routes'
assert_contains 'If `ms_graph_query` is unavailable, report that as a startup/plugin-load or tool-registry problem on the pod'
assert_contains 'action="login_start"'
assert_contains 'Use the tool directly and immediately.'
assert_contains 'verification_uri_complete'
assert_contains 'verification_uri'
assert_contains 'user_code'
assert_contains 'device login URL'
assert_contains 'login code'
assert_contains 'Present the login details immediately after `login_start` returns.'
assert_contains 'wait for the user to confirm they completed browser sign-in'
assert_contains 'action="login_poll"'
assert_contains '## Jira Login'
assert_contains '`jira_query`'
assert_contains '`jira_query` is expected to be available on this pod.'
assert_contains 'action="login_setup"'
assert_contains 'Jira API URL for this pod'
assert_contains '${JIRA_BASE_URL:-https://dame-technologies.atlassian.net}'
assert_contains 'Jira email'
assert_contains 'Jira API token'
assert_contains 'defaultProjectKeys'
assert_contains '## Inter-Pod Delegation'
assert_contains '`pod_delegate`'
assert_contains 'POST /v1/responses'

echo "bootstrap template checks passed"
