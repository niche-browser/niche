#!/bin/bash
# Mutated copies of the importer fixtures through their parsers, under AddressSanitizer
# (Tests/FuzzTests.swift). NICHE_FUZZ_ITERATIONS (default 20000) and NICHE_FUZZ_SEED; a crash
# leaves its input in build/fuzz/crash-input.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-fuzz.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p build/fuzz
xcrun swiftc -swift-version 5 -parse-as-library -sanitize=address -g \
  Packages/NicheCore/Sources/NicheCore/*.swift Packages/NicheCore/Sources/NicheCore/Perf/*.swift Sources/Niche/Perf/Perf.swift \
  Sources/Niche/Services/Import/*.swift \
  Sources/Niche/Services/SidebarStore.swift Sources/Niche/Services/SidebarIntegrity.swift Sources/Niche/Services/Persistence.swift \
  Sources/Niche/Services/GitHubLiveClient.swift Sources/Niche/Services/FaviconCache.swift \
  Sources/Niche/Services/SafeStorage.swift Sources/Niche/Services/NicheLog.swift Sources/Niche/Services/Scheduler.swift \
  Tests/FuzzTests.swift -o "$TEST_DIR/fuzz"
NICHE_FUZZ_OUT="$PWD/build/fuzz" "$TEST_DIR/fuzz"
