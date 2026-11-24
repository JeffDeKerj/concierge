#!/usr/bin/env bash
# Run the tests with the same build flags as make_app.sh. The app under test
# is pointed at a throwaway project folder and at Scripts/claude-stub.sh, so
# no test ever touches briefings/ or runs the real claude.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/swift-build-flags.sh
CLAUDE_ASSISTANT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-assistant-test.XXXXXX")"
export CLAUDE_ASSISTANT_DIR
export CLAUDE_ASSISTANT_CLAUDE_BIN="$PWD/Scripts/claude-stub.sh"
trap 'rm -rf "$CLAUDE_ASSISTANT_DIR"' EXIT
swift test "${SWIFT_TEST_FLAGS[@]}" "$@"
