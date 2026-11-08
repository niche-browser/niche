#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-extension-state.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} Sources/Niche/Services/Import/ExtensionImporter.swift \
  Tests/ExtensionStateTests.swift -o "$TEST_DIR/extension-state-tests"
"$TEST_DIR/extension-state-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/extension-state-tests" "$NICHE_TEST_KEEP/"
