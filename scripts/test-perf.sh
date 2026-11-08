#!/bin/bash
# The performance recorder (#91) on a real main run loop: stalls, hang files with a stack, the
# session marker, ownership and the recording switch. Its files go to a temporary folder.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-perf-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  Packages/NicheCore/Sources/NicheCore/Perf/*.swift Sources/Niche/Perf/Perf.swift Sources/Niche/Perf/MainLoopObserver.swift \
  Sources/Niche/Perf/PerfSamplers.swift Sources/Niche/Perf/PerfFiles.swift Sources/Niche/Perf/PerfRecorder.swift \
  Sources/Niche/Services/NicheLog.swift Sources/Niche/Services/Persistence.swift \
  Tests/PerfTests.swift -o "$TEST_DIR/perf-tests"
"$TEST_DIR/perf-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/perf-tests" "$NICHE_TEST_KEEP/"
