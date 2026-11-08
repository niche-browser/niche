#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/niche-extension-migration.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name NicheCEF \
  Tests/ExtensionStoreSupport/NicheCEF.swift -o "$TEST_DIR/libNicheCEF.dylib" \
  -emit-module-path "$TEST_DIR/NicheCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  -I "$TEST_DIR" -L "$TEST_DIR" -lNicheCEF -Xlinker -rpath -Xlinker "$TEST_DIR" \
  Packages/NicheCore/Sources/NicheCore/ExtensionProfiles.swift \
  Packages/NicheCore/Sources/NicheCore/WebStoreInstalls.swift \
  Packages/NicheCore/Sources/NicheCore/PinnedExtensions.swift \
  Packages/NicheCore/Sources/NicheCore/ExtensionActionState.swift \
  Packages/NicheCore/Sources/NicheCore/ExtensionBadge.swift \
  Packages/NicheCore/Sources/NicheCore/ExtensionProxyControl.swift \
  Sources/Niche/Services/Import/ExtensionImporter.swift Sources/Niche/Services/ExtensionStore.swift \
  Tests/ExtensionStoreSupport/AppServices.swift Tests/ExtensionStoreMigrationTests.swift \
  -o "$TEST_DIR/extension-migration-tests"
NICHE_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/extension-migration-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/extension-migration-tests" "$NICHE_TEST_KEEP/"
