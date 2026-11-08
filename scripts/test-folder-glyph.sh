#!/bin/bash
# Folder emblems: real AppKit layer projection and bitmap pixels, without CEF or visible windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/niche-folder-glyph.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cp -R resources/fonts "$TEST_DIR/fonts"
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  Packages/NicheCore/Sources/NicheCore/FolderSymbol.swift Sources/Niche/UI/Sidebar/FolderSymbolImages.swift \
  Sources/Niche/UI/Sidebar/LiveFolderMarks.swift \
  Sources/Niche/UI/Sidebar/List/FolderGlyphView.swift Tests/FolderGlyphTests.swift \
  -o "$TEST_DIR/folder-glyph-tests"
"$TEST_DIR/folder-glyph-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/folder-glyph-tests" "$NICHE_TEST_KEEP/"
