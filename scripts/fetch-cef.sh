#!/bin/bash
# Downloads the pinned CEF binary distribution into vendor/cef and builds the
# C++ wrapper library. Safe to re-run; skips what is already there.
#
# Niche ships its own CEF build (scripts/build-cef.sh: H.264/AAC plus the fixes in
# scripts/cef-patches), published as a GitHub release asset by scripts/publish-cef.sh.
# CEF_URL=https://cef-builds.spotifycdn.com/<name>.tar.bz2 fetches Spotify's stock
# build instead (no H.264/AAC).
set -euo pipefail
cd "$(dirname "$0")/.."

CEF_VERSION="${CEF_VERSION:-156.0.26+g8ea0c73+chromium-156.0.8078.88}"
# Follow the host CPU by default (macosarm64 / macosx64); CEF_ARCH overrides.
# Note: Spotify's CEF builds index names the Intel platform "macosx64".
ARCH="${CEF_ARCH:-$([ "$(uname -m)" = arm64 ] && echo macosarm64 || echo macosx64)}"
NAME="cef_binary_${CEF_VERSION}_${ARCH}_minimal"
# Bump the suffix (niche2, …) when the build changes but CEF_VERSION does not.
CEF_RELEASE="${CEF_RELEASE:-cef-${CEF_VERSION%%+*}-niche1}"
URL="${CEF_URL:-https://github.com/niche-browser/niche/releases/download/${CEF_RELEASE}/cef_binary_${ARCH}_minimal.tar.bz2}"

mkdir -p vendor
# A different pinned build replaces vendor/cef.
[ -d vendor/cef/Release ] && [ ! -f vendor/cef/.niche-source ] && echo "https://cef-builds.spotifycdn.com/${NAME}.tar.bz2" > vendor/cef/.niche-source
if [ -d vendor/cef/Release ] && [ "$(cat vendor/cef/.niche-source)" != "$URL" ]; then
  echo "CEF build changed, replacing vendor/cef"
  rm -rf vendor/cef
fi
if [ ! -d vendor/cef/Release ]; then
  echo "Downloading ${NAME} from ${URL%/*}..."
  rm -rf vendor/cef-download
  mkdir -p vendor/cef-download
  curl -fL --progress-bar -o "vendor/cef-download/${NAME}.tar.bz2" "$URL"
  tar -xjf "vendor/cef-download/${NAME}.tar.bz2" -C vendor/cef-download
  rm -rf vendor/cef
  mv "vendor/cef-download/${NAME}" vendor/cef
  rm -rf vendor/cef-download
  echo "$URL" > vendor/cef/.niche-source
fi

if [ ! -f vendor/cef/build/libcef_dll_wrapper/libcef_dll_wrapper.a ]; then
  echo "Building libcef_dll_wrapper..."
  case "$ARCH" in
    macosarm64) TARGET_ARCH=arm64 ;;
    *)          TARGET_ARCH=x86_64 ;;
  esac
  cmake -S vendor/cef -B vendor/cef/build -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH="$TARGET_ARCH" -DUSE_SANDBOX=ON \
    -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH" > vendor/cef/build-configure.log
  cmake --build vendor/cef/build --target libcef_dll_wrapper -j "$(sysctl -n hw.ncpu)" > vendor/cef/build-wrapper.log
fi

# Chromium encrypts cookies, passwords and card numbers with a secret from the login
# Keychain item "Chromium Safe Storage", which every Chromium-based app without its own
# name shares. Niche's is "Niche Safe Store" (SafeStorage.swift creates it before Chromium
# starts; scripts/cef-patches/keychain-service-name.patch compiles the name in). Stop rather
# than run a framework that looks for another item: Niche would encrypt with one secret and
# Chromium decrypt with another. Stock CEF builds (CEF_URL to spotifycdn.com) still use the
# shared item; NICHE_ALLOW_STOCK_CEF=1 accepts that.
FRAMEWORK_BIN="vendor/cef/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework"
if [ "${NICHE_ALLOW_STOCK_CEF:-0}" != 1 ]; then
  LC_ALL=C grep -qa "Niche Safe Store" "$FRAMEWORK_BIN" || {
    echo "This CEF build names no Niche Safe Store; build it with scripts/build-cef.sh" >&2; exit 1; }
fi
echo "CEF ready: vendor/cef"
