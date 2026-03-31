#!/bin/bash

set -euo pipefail

PLUGIN_JSON="plugins/ms-graph-query/openclaw.plugin.json"
PLUGIN_JS="plugins/ms-graph-query/index.js"
DEPLOY_SCRIPT="openclaw-deploy.sh"

MIN_SCOPE='offline_access openid profile User.Read Calendars.ReadWrite Mail.ReadWrite Files.ReadWrite Sites.Read.All'

assert_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -Fq -- "$pattern" "$file"; then
        echo "missing expected pattern in $file: $pattern" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"

    if grep -Fq -- "$pattern" "$file"; then
        echo "unexpected pattern in $file: $pattern" >&2
        exit 1
    fi
}

assert_contains "$PLUGIN_JSON" "\"default\": \"$MIN_SCOPE\""
assert_contains "$PLUGIN_JS" "default: \"$MIN_SCOPE\""
assert_contains "$PLUGIN_JS" "\"$MIN_SCOPE\""
assert_contains "$DEPLOY_SCRIPT" "\"delegatedScope\": \"$MIN_SCOPE\""

assert_contains "$DEPLOY_SCRIPT" '"/v1.0/me"'
assert_contains "$DEPLOY_SCRIPT" '"/v1.0/sites"'
assert_contains "$DEPLOY_SCRIPT" '"/v1.0/drives"'

assert_not_contains "$DEPLOY_SCRIPT" 'Mail.Send'
assert_not_contains "$DEPLOY_SCRIPT" 'Sites.ReadWrite.All'
assert_not_contains "$DEPLOY_SCRIPT" '"/v1.0/users"'
assert_not_contains "$DEPLOY_SCRIPT" '"/v1.0/search/query"'

echo "ms-graph least-privilege checks passed"
