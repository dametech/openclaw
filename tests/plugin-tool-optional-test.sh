#!/bin/bash

set -euo pipefail

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

MS_GRAPH_PLUGIN="openclaw/plugins/ms-graph-query/index.js"
JIRA_PLUGIN="openclaw/plugins/jira-query/index.js"
POD_DELEGATE_PLUGIN="openclaw/plugins/pod-delegate/index.js"

assert_contains "$MS_GRAPH_PLUGIN" 'name: "ms_graph_query"'
assert_contains "$JIRA_PLUGIN" 'name: "jira_query"'
assert_contains "$POD_DELEGATE_PLUGIN" 'name: "pod_delegate"'

assert_not_contains "$MS_GRAPH_PLUGIN" '{ optional: true }'
assert_not_contains "$JIRA_PLUGIN" '{ optional: true }'
assert_not_contains "$POD_DELEGATE_PLUGIN" '{ optional: true }'

echo "plugin tool optional checks passed"
