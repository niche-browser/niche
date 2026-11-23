#!/bin/bash
# Builds Shields, Niche's filter engine (Sources/NicheShields, Rust), into
# vendor/shields/libniche_shields.a, which NicheCEF and NicheHelper link. Needs a Rust toolchain
# (https://rustup.rs). Cargo decides what is stale, so calling this before every build is cheap.
#   scripts/build-shields.sh          build for arm64 and x86_64, joined into one library
#   scripts/build-shields.sh --test   run the engine's own tests too
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/vendor/shields"
if ! command -v cargo >/dev/null 2>&1; then
  [ -x "$HOME/.cargo/bin/cargo" ] && export PATH="$HOME/.cargo/bin:$PATH"
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "Shields needs Rust: install it from https://rustup.rs, then run this again." >&2
  exit 1
fi
export CARGO_TARGET_DIR="$ROOT/.build/shields"
# The app's deployment target, so the linker doesn't warn about newer objects.
export MACOSX_DEPLOYMENT_TARGET=14.0
cd Sources/NicheShields
if [ "${1:-}" = "--test" ]; then cargo test --release --locked --quiet; fi
# Both CPUs every time: one library links into either slice of a universal app (NICHE_UNIVERSAL),
# and a build for this Mac alone links it too.
TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
if command -v rustup >/dev/null 2>&1; then
  INSTALLED="$(rustup target list --installed)"
  for t in "${TARGETS[@]}"; do grep -qx "$t" <<< "$INSTALLED" || rustup target add "$t" >/dev/null; done
fi
LIBS=()
for t in "${TARGETS[@]}"; do
  cargo build --release --locked --quiet --target "$t"
  LIBS+=("$CARGO_TARGET_DIR/$t/release/libniche_shields.a")
done
mkdir -p "$OUT"
lipo -create "${LIBS[@]}" -output "$CARGO_TARGET_DIR/libniche_shields.a"
if ! cmp -s "$CARGO_TARGET_DIR/libniche_shields.a" "$OUT/libniche_shields.a"; then cp "$CARGO_TARGET_DIR/libniche_shields.a" "$OUT/libniche_shields.a"; fi
