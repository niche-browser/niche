#!/bin/bash
# The engine bridge's decisions that need no CEF or Cocoa (Sources/NicheCEF/*.h, plain C++).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/niche-engine-policy-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang++ -std=c++20 -Wall -Wextra -Werror Tests/Engine/ProtocolPolicyTests.cc -o "$TEST_DIR/engine-policy-tests"
"$TEST_DIR/engine-policy-tests"
