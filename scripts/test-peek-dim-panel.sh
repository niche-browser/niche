#!/bin/bash
# The click catcher behind a Peek (PeekDimPanel) and the focus rule for page windows hung on Niche windows (ChromiumChildFocus).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/niche-peek-panel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  Packages/NicheCore/Sources/NicheCore/PeekLayout.swift Sources/Niche/UI/Windows/PeekDimPanel.swift \
  Sources/Niche/UI/Windows/ChromiumChildFocus.swift Tests/PeekDimPanelTests.swift \
  -o "$TEST_DIR/peek-panel-tests"
"$TEST_DIR/peek-panel-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/peek-panel-tests" "$NICHE_TEST_KEEP/"
