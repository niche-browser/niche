#!/bin/bash
# Compile the real manager against a deterministic bridge; no Chromium or profile I/O.
set -euo pipefail
cd "$(dirname "$0")/.."
MANAGER_SOURCE="${1:-Sources/Niche/Services/BrowserManager.swift}"
TEST_DIR="$(mktemp -d /tmp/niche-lifecycle-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name NicheCEF \
  Tests/BrowserManagerSupport/NicheCEF.swift -o "$TEST_DIR/libNicheCEF.dylib" \
  -emit-module-path "$TEST_DIR/NicheCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" -L "$TEST_DIR" -lNicheCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  "$MANAGER_SOURCE" Sources/Niche/Services/NowPlaying.swift Sources/Niche/Services/PageScript.swift Sources/Niche/Services/Scheduler.swift Sources/Niche/Services/DevToolsToggle.swift Sources/Niche/Services/NicheLog.swift Sources/Niche/Services/PageProbe.swift Sources/Niche/Services/Persistence.swift \
  Sources/Niche/Perf/Perf.swift Packages/NicheCore/Sources/NicheCore/Perf/*.swift Packages/NicheCore/Sources/NicheCore/ExtensionPageRetry.swift Packages/NicheCore/Sources/NicheCore/PermissionPrompt.swift Packages/NicheCore/Sources/NicheCore/TabSleepPolicy.swift Packages/NicheCore/Sources/NicheCore/ProtectedMedia.swift Sources/Niche/Services/WebKit/PageEngines.swift Tests/Support/ManualScheduler.swift Tests/BrowserManagerSupport/AppServices.swift \
  Packages/NicheCore/Sources/NicheCore/DialogActions.swift Packages/NicheCore/Sources/NicheCore/Boost.swift Packages/NicheCore/Sources/NicheCore/PictureInPictureLayout.swift Tests/BrowserManagerLifecycleTests.swift -o "$TEST_DIR/lifecycle-tests"
# A data folder of its own: PageEngines keeps protected-media.json there, not in the real Niche's.
NICHE_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/lifecycle-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/lifecycle-tests" "$NICHE_TEST_KEEP/"
