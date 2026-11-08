#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp/}niche-dialog-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  Packages/NicheCore/Sources/NicheCore/*.swift Packages/NicheCore/Sources/NicheCore/Perf/*.swift \
  Sources/Niche/UI/Colors.swift Sources/Niche/UI/Design.swift Sources/Niche/UI/BrandMark.swift \
  Sources/Niche/UI/Windows/DialogComponents.swift Sources/Niche/UI/Windows/AppDialog.swift \
  Tests/DialogTests.swift -o "$TEST_DIR/dialog-tests"
"$TEST_DIR/dialog-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/dialog-tests" "$NICHE_TEST_KEEP/"
