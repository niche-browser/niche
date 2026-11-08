#!/bin/bash
# Decisions pulled out of the window controllers (extension clicks, DevTools toggle, feature flags).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-policy-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${NICHE_TEST_SWIFTC_FLAGS:-} \
  Sources/Niche/UI/Windows/ExtensionLaunch.swift Sources/Niche/Services/DevToolsToggle.swift Sources/Niche/App/FeatureFlags.swift \
  Sources/Niche/App/AppDelegate+Handoff.swift \
  Tests/PolicyTests.swift -o "$TEST_DIR/policy-tests"
"$TEST_DIR/policy-tests"
[ -z "${NICHE_TEST_KEEP:-}" ] || cp "$TEST_DIR/policy-tests" "$NICHE_TEST_KEEP/"
