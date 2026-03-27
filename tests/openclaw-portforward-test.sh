#!/bin/bash

set -euo pipefail

SCRIPT="openclaw-portforward.sh"

assert_contains() {
    local pattern="$1"

    if ! grep -Fq -- "$pattern" "$SCRIPT"; then
        echo "missing expected pattern: $pattern" >&2
        exit 1
    fi
}

assert_contains 'RELEASE_NAME="openclaw"'
assert_contains 'echo -n "Enter instance name [openclaw]: "'
assert_contains 'RELEASE_NAME="$input_name"'
assert_contains 'deployment/$RELEASE_NAME'
assert_contains 'svc/$RELEASE_NAME'
assert_contains 'app.kubernetes.io/instance=$RELEASE_NAME'

if grep -Fq -- 'deployment/openclaw' "$SCRIPT"; then
    echo "unexpected hardcoded deployment/openclaw in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'svc/openclaw' "$SCRIPT"; then
    echo "unexpected hardcoded svc/openclaw in $SCRIPT" >&2
    exit 1
fi

if grep -Fq -- 'app.kubernetes.io/name=openclaw' "$SCRIPT"; then
    echo "unexpected hardcoded app.kubernetes.io/name=openclaw selector in $SCRIPT" >&2
    exit 1
fi

echo "openclaw-portforward.sh checks passed"
