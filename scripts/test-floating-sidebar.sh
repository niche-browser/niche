#!/bin/bash
# Production sidebar lifecycle and shared hit geometry; no CEF/profile/input events.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-sidebar-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} Sources/Niche/UI/Windows/FloatingSidebarGeometry.swift \
  Sources/Niche/UI/Windows/FloatingSidebar.swift Packages/NicheCore/Sources/NicheCore/SidebarBackdrop.swift \
  Tests/FloatingSidebarTests.swift \
  -o "$TEST_DIR/sidebar-tests"
"$TEST_DIR/sidebar-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/sidebar-tests" "$NICHE_TEST_KEEP/"
