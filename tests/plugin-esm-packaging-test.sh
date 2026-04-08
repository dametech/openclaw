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

assert_file() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "missing expected file: $file" >&2
        exit 1
    fi
}

for plugin_dir in openclaw/plugins/ms-graph-query openclaw/plugins/jira-query openclaw/plugins/pod-delegate; do
    assert_file "$plugin_dir/package.json"
    assert_contains "$plugin_dir/package.json" '"type": "module"'
done

echo "plugin ESM packaging checks passed"
