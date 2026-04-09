#!/bin/bash

set -euo pipefail

FILE="openclaw/workspace/AGENTS.md"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$FILE"; then
        echo "missing expected pattern in $FILE: $pattern" >&2
        exit 1
    fi
}

if [ ! -f "$FILE" ]; then
    echo "missing expected file: $FILE" >&2
    exit 1
fi

assert_contains '## Operating Instructions'
assert_contains 'Read `INSTRUCTIONS.md` at the start of every session.'
assert_contains 'mandatory plan-first protocol, tool discipline, safety rules, and'
assert_contains 'communication standards that govern all agent behaviour.'

echo "workspace AGENTS checks passed"
