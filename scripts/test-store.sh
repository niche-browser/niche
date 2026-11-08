#!/bin/bash
# The production store, AppComposition and importers on a manual clock; no CEF or AppKit windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-store-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  Packages/NicheCore/Sources/NicheCore/*.swift Packages/NicheCore/Sources/NicheCore/Perf/*.swift Sources/Niche/Perf/Perf.swift \
  Sources/Niche/Services/Import/*.swift \
  Sources/Niche/Services/SidebarStore.swift Sources/Niche/Services/SidebarIntegrity.swift Sources/Niche/Services/Persistence.swift \
  Sources/Niche/Services/GitHubLiveClient.swift Sources/Niche/Services/FaviconCache.swift Sources/Niche/Services/SafeStorage.swift \
  Sources/Niche/Services/NicheLog.swift Sources/Niche/Services/Scheduler.swift \
  Sources/Niche/App/AppComposition.swift Sources/Niche/App/FeatureFlags.swift \
  Tests/Support/ManualScheduler.swift Tests/StoreTests.swift -o "$TEST_DIR/store-tests"
"$TEST_DIR/store-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/store-tests" "$NICHE_TEST_KEEP/"
