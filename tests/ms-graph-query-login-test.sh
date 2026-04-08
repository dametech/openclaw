#!/bin/bash

set -euo pipefail

PLUGIN_JS="openclaw/plugins/ms-graph-query/index.js"

if [ ! -f "$PLUGIN_JS" ]; then
    echo "missing expected file: $PLUGIN_JS" >&2
    exit 1
fi

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$PLUGIN_JS"; then
        echo "missing expected pattern in $PLUGIN_JS: $pattern" >&2
        exit 1
    fi
}

assert_contains 'device_login_url'
assert_contains 'device_login_url_complete'
assert_contains 'login_code'
assert_contains 'verification_uri_complete: body.verification_uri_complete'
assert_contains 'user_code: body.user_code'

echo "ms-graph login payload checks passed"
