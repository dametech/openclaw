#!/bin/bash

set -euo pipefail

MANIFEST="slack-app-manifest.yaml"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$MANIFEST"; then
        echo "missing expected pattern in $MANIFEST: $pattern" >&2
        exit 1
    fi
}

if [ ! -f "$MANIFEST" ]; then
    echo "missing expected file: $MANIFEST" >&2
    exit 1
fi

assert_contains 'socket_mode_enabled: true'
assert_contains 'messages_tab_enabled: true'
assert_contains '- chat:write'
assert_contains '- chat:write.public'
assert_contains '- chat:write.customize'
assert_contains '- channels:join'
assert_contains '- channels:history'
assert_contains '- channels:read'
assert_contains '- groups:history'
assert_contains '- groups:write'
assert_contains '- im:history'
assert_contains '- im:read'
assert_contains '- im:write'
assert_contains '- app_mentions:read'
assert_contains '- files:read'
assert_contains '- files:write'

echo "slack app manifest checks passed"
