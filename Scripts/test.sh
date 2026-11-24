#!/usr/bin/env bash
# Run the tests with the same build flags as make_app.sh. The app under test
# is pointed at a throwaway project folder and at Scripts/claude-stub.sh, so
# no test ever touches briefings/ or runs the real claude.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/swift-build-flags.sh
CONCIERGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/concierge-test.XXXXXX")"
export CONCIERGE_DIR
export CONCIERGE_CLAUDE_BIN="$PWD/Scripts/claude-stub.sh"
trap 'rm -rf "$CONCIERGE_DIR"' EXIT
swift test "${SWIFT_TEST_FLAGS[@]}" "$@"
