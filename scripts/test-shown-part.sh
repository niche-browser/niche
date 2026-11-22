#!/bin/bash
# Whether the pointer is on a view (ShownPart.swift): real AppKit views, without CEF or a visible window.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/niche-shown-part.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  Sources/Niche/UI/ShownPart.swift Tests/ShownPartTests.swift -o "$TEST_DIR/shown-part-tests"
"$TEST_DIR/shown-part-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/shown-part-tests" "$NICHE_TEST_KEEP/"
