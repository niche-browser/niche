#!/bin/bash
# Downloads the pinned CEF binary distribution into vendor/cef and builds the
# C++ wrapper library. Safe to re-run; skips what is already there.
#
# Niche ships its own CEF build (scripts/build-cef.sh: H.264/AAC plus the fixes in
# scripts/cef-patches), published as a GitHub release asset by scripts/publish-cef.sh.
# CEF_URL=https://cef-builds.spotifycdn.com/<name>.tar.bz2 fetches Spotify's stock
# build instead (no H.264/AAC).
#
# NICHE_UNIVERSAL=1 (release builds and CI) also fetches the Intel build into vendor/cef-x64
# and joins the two into vendor/cef-universal/Chromium Embedded Framework.framework, which runs
# on both CPUs: the two builds differ only in four Mach-O files (lipo'd) and two resources named
# after their CPU (v8_context_snapshot.<cpu>.bin, webui_code_cache.<cpu>.pak, both kept). The C++
# wrapper is always built for both CPUs, so one library links either slice.
set -euo pipefail
cd "$(dirname "$0")/.."

CEF_VERSION="${CEF_VERSION:-158.0.3+g8c29be2+chromium-158.0.8127.18}"
# Follow the host CPU by default (macosarm64 / macosx64); CEF_ARCH overrides.
# Note: Spotify's CEF builds index names the Intel platform "macosx64".
ARCH="${CEF_ARCH:-$([ "$(uname -m)" = arm64 ] && echo macosarm64 || echo macosx64)}"
NAME="cef_binary_${CEF_VERSION}_${ARCH}_minimal"
# Bump the suffix (niche2, …) when the build changes but CEF_VERSION does not.
CEF_RELEASE="${CEF_RELEASE:-cef-${CEF_VERSION%%+*}-niche3}"
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

WRAPPER=vendor/cef/build/libcef_dll_wrapper/libcef_dll_wrapper.a
if [ ! -f "$WRAPPER" ] || [ "$(lipo -archs "$WRAPPER" 2>/dev/null | tr ' ' '\n' | sort | xargs)" != "arm64 x86_64" ]; then
  # Once per CPU (CEF's CMake files set the architecture from PROJECT_ARCH alone), then joined.
  echo "Building libcef_dll_wrapper (arm64 and x86_64)..."
  for arch in arm64 x86_64; do
    cmake -S vendor/cef -B "vendor/cef/build-$arch" -G "Unix Makefiles" \
      -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH="$arch" -DUSE_SANDBOX=ON \
      -DCMAKE_OSX_ARCHITECTURES="$arch" > "vendor/cef/build-configure-$arch.log"
    cmake --build "vendor/cef/build-$arch" --target libcef_dll_wrapper -j "$(sysctl -n hw.ncpu)" > "vendor/cef/build-wrapper-$arch.log"
  done
  mkdir -p "$(dirname "$WRAPPER")"
  lipo -create vendor/cef/build-{arm64,x86_64}/libcef_dll_wrapper/libcef_dll_wrapper.a -output "$WRAPPER"
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

if [ "${NICHE_UNIVERSAL:-0}" = 1 ]; then
  OTHER="$([ "$ARCH" = macosarm64 ] && echo macosx64 || echo macosarm64)"
  OTHER_NAME="cef_binary_${CEF_VERSION}_${OTHER}_minimal"
  OTHER_URL="${CEF_URL_OTHER:-https://github.com/niche-browser/niche/releases/download/${CEF_RELEASE}/cef_binary_${OTHER}_minimal.tar.bz2}"
  if [ ! -d vendor/cef-other/Release ] || [ "$(cat vendor/cef-other/.niche-source 2>/dev/null)" != "$OTHER_URL" ]; then
    echo "Downloading ${OTHER_NAME} from ${OTHER_URL%/*}..."
    rm -rf vendor/cef-other vendor/cef-download
    mkdir -p vendor/cef-download
    curl -fL --progress-bar -o "vendor/cef-download/${OTHER_NAME}.tar.bz2" "$OTHER_URL"
    tar -xjf "vendor/cef-download/${OTHER_NAME}.tar.bz2" -C vendor/cef-download
    mv "vendor/cef-download/${OTHER_NAME}" vendor/cef-other
    rm -rf vendor/cef-download
    echo "$OTHER_URL" > vendor/cef-other/.niche-source
  fi
  FW="Chromium Embedded Framework.framework"
  U="vendor/cef-universal/$FW"
  STAMP="$(cat vendor/cef/.niche-source vendor/cef-other/.niche-source)"
  if [ ! -d "$U" ] || [ "$(cat vendor/cef-universal/.niche-source 2>/dev/null)" != "$STAMP" ]; then
    echo "Joining the two CEF builds into one universal framework..."
    rm -rf vendor/cef-universal
    mkdir -p vendor/cef-universal
    ditto "vendor/cef/Release/$FW" "$U"
    # The files the two builds both have but differ in are Mach-O: lipo them. Anything else that
    # differs would mean the builds don't match.
    (cd "vendor/cef/Release/$FW" && find . -type f) | while IFS= read -r f; do
      mine="vendor/cef/Release/$FW/$f" theirs="vendor/cef-other/Release/$FW/$f"
      [ -f "$theirs" ] && ! cmp -s "$mine" "$theirs" || continue
      if lipo -archs "$mine" >/dev/null 2>&1; then
        lipo -create "$mine" "$theirs" -output "$U/$f"
      else
        echo "The CEF builds differ in $f, which is not a binary: they are not one build" >&2; exit 1
      fi
    done
    # What only the other build has (its CPU's V8 snapshot and WebUI code cache).
    (cd "vendor/cef-other/Release/$FW" && find . -type f) | while IFS= read -r f; do
      [ -f "vendor/cef/Release/$FW/$f" ] || { mkdir -p "$(dirname "$U/$f")"; cp "vendor/cef-other/Release/$FW/$f" "$U/$f"; }
    done
    for bin in "$U/Chromium Embedded Framework" "$U"/Libraries/*.dylib; do
      [ "$(lipo -archs "$bin" | tr ' ' '\n' | sort | xargs)" = "arm64 x86_64" ] || { echo "$bin is not universal" >&2; exit 1; }
    done
    echo "$STAMP" > vendor/cef-universal/.niche-source
  fi
  echo "CEF ready: vendor/cef-universal (arm64 and x86_64)"
fi
