#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-popup-candidate.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} Sources/Niche/UI/Windows/ExtensionPopupCandidate.swift \
  Tests/ExtensionPopupCandidateTests.swift -o "$TEST_DIR/candidate-tests"
"$TEST_DIR/candidate-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/candidate-tests" "$NICHE_TEST_KEEP/"
