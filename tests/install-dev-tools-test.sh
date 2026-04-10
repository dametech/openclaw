#!/bin/bash

set -euo pipefail

INSTALL_SCRIPT="scripts/install-dev-tools.sh"
README_FILE="README.md"
TOOLS_FILE="openclaw/workspace/TOOLS.md"
CONTAINER_TOOLS_DOC="docs/CONTAINER-TOOLS.md"

assert_not_contains() {
    local file="$1"
    local pattern="$2"

    if grep -Fq -- "$pattern" "$file"; then
        echo "unexpected pattern in $file: $pattern" >&2
        exit 1
    fi
}

assert_not_contains "$INSTALL_SCRIPT" "@openai/codex"
assert_not_contains "$INSTALL_SCRIPT" "CODEX_VERSION="
assert_not_contains "$INSTALL_SCRIPT" "Codex CLI"
assert_not_contains "$README_FILE" "- \`codex\`"
assert_not_contains "$TOOLS_FILE" "- \`codex\`"
assert_not_contains "$CONTAINER_TOOLS_DOC" "| codex |"

echo "install-dev-tools.sh checks passed"
