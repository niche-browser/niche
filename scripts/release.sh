#!/bin/bash
# Full distributable build: build, sign, notarize, package, notarize the DMG, and
# write the Sparkle appcast for the update archive.
#   NICHE_VERSION=0.1.0 NICHE_SIGN_IDENTITY="Developer ID Application: …" scripts/release.sh
# Without NICHE_SIGN_IDENTITY it still produces an ad-hoc build and packages, so
# the pipeline can be exercised before certificates exist. The appcast needs the
# update signing key (SPARKLE_PRIVATE_KEY, or the "niche" key in the login keychain).
set -euo pipefail
cd "$(dirname "$0")/.."
export NICHE_VERSION="${NICHE_VERSION:-0.1.0}"
# Release builds carry the update feed (scripts/build.sh drops it otherwise).
export NICHE_RELEASE=1
IDENTITY="${NICHE_SIGN_IDENTITY:--}"

scripts/build.sh release
APP="build/Niche.app"

if [ "$IDENTITY" != "-" ]; then
  # Notarize the app first (as a zip), staple it, then package the stapled app.
  TMPZIP="$(mktemp -d /tmp/niche-notarize.XXXXXX)/Niche.zip"
  ditto -c -k --keepParent "$APP" "$TMPZIP"
  scripts/notarize.sh "$TMPZIP" "$APP"
  rm -rf "$(dirname "$TMPZIP")"
fi

scripts/package.sh "$APP"

if [ "$IDENTITY" != "-" ]; then
  scripts/notarize.sh "build/dist/Niche.dmg"
  # Re-zip the stapled app so the zip download carries the ticket too.
  ditto -c -k --keepParent "$APP" "build/dist/Niche.zip"
  (cd build/dist && shasum -a 256 Niche.zip Niche.dmg > SHA256SUMS.txt)
  # On its own line so set -e fails the release when Gatekeeper rejects the app.
  spctl --assess --type execute --verbose=2 "$APP"
  echo "Gatekeeper accepts $APP"
else
  echo "Ad-hoc build: not notarized. Set NICHE_SIGN_IDENTITY and notary credentials for a distributable build." >&2
fi
# Installed copies update from the zip; the appcast must sign the final one.
scripts/appcast.sh build/dist/Niche.zip "$APP" "${NICHE_RELEASE_NOTES:-}"
echo "Release artifacts in build/dist"
