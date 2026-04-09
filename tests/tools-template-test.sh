#!/bin/bash

set -euo pipefail

TOOLS_FILE="openclaw/workspace/TOOLS.md"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$TOOLS_FILE"; then
        echo "missing expected pattern in $TOOLS_FILE: $pattern" >&2
        exit 1
    fi
}

if [ ! -f "$TOOLS_FILE" ]; then
    echo "missing expected file: $TOOLS_FILE" >&2
    exit 1
fi

assert_contains '## Custom Gateway Tools On This Pod'
assert_contains '## Channels On This Pod'
assert_contains '`slack`'
assert_contains 'setup-slack-integration.sh'
assert_contains 'disabled Slack channel block by default'
assert_contains '`msteams`'
assert_contains 'setup-msteams-integration.sh'
assert_contains 'configured Teams channel block'
assert_contains '`ms_graph_query`'
assert_contains '`jira_query`'
assert_contains '`pod_delegate`'
assert_contains '## Optional Repo Plugin'
assert_contains 'setup-msteams-integration.sh'
assert_contains '## Local Shell Tooling In The Pod'
assert_contains '~/.openclaw/bin'
assert_contains '`jq`'
assert_contains '`kubectl`'
assert_contains '`helm`'
assert_contains '`gh`'
assert_contains '`go`'
assert_contains '`terraform`'
assert_contains '`op`'
assert_contains '`aws`'
assert_contains '`codex`'
assert_contains '`curl`'
assert_contains '`tar`'
assert_contains '`gzip`'
assert_contains '`unzip`'
assert_contains 'does not by itself make them agent-callable structured tools'

echo "tools template checks passed"
