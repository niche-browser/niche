#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/niche-popup-window.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name NicheCEF \
  Tests/BrowserManagerSupport/NicheCEF.swift -o "$TEST_DIR/libNicheCEF.dylib" \
  -emit-module-path "$TEST_DIR/NicheCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" -L "$TEST_DIR" -lNicheCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  Sources/Niche/UI/Windows/ExtensionPopupWindow.swift Tests/ExtensionPopupWindowTests.swift \
  -o "$TEST_DIR/popup-window-tests"
"$TEST_DIR/popup-window-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/popup-window-tests" "$NICHE_TEST_KEEP/"
