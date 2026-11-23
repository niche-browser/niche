#!/bin/bash
# An update from the latest release to this build keeps the profile (Tests/Scenarios/upgrade.scenario):
# the release makes a profile, this build opens it, and the run fails if a cookie, a page's site
# data or the open tab is gone, or Chromium reset its protected settings (the extension list).
# 0.1.11 shipped Chromium 158, which could no longer read what 156 had written: everyone it
# updated was signed out of every site and lost every extension (22 Nov 2026).
#
#   scripts/update-from-release.sh                     the latest release → build/Niche.app
#   scripts/update-from-release.sh v0.1.10             that release → build/Niche.app
#   scripts/update-from-release.sh <previous Niche.app> an app on disk → build/Niche.app
#
# NICHE_APP picks the new build. Both run as ad-hoc signed copies: a Developer ID build would use
# the login Keychain's "Niche Safe Store" item, which an unsigned build can't read without asking
# (a dialog on a Mac, a failure on CI). Ad hoc, both use Chromium's mock Keychain, through the same
# key providers. Budgets only report: this checks data, and CI's build is a debug one.
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${NICHE_APP:-$PWD/build/Niche.app}"
[ -x "$NEW/Contents/MacOS/Niche" ] || { echo "No Niche at $NEW (scripts/build.sh)"; exit 2; }
WORK="$(cd "$(mktemp -d /tmp/niche-upgrade.XXXXXX)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

FROM="${1:-}"
if [ -d "$FROM" ]; then
  PREVIOUS="$FROM"
else
  TAG="${FROM:-$(gh release view --json tagName -q .tagName)}"
  echo "Previous release: $TAG"
  gh release download "$TAG" -p Niche.zip -D "$WORK"
  ditto -x -k "$WORK/Niche.zip" "$WORK/release"
  PREVIOUS="$WORK/release/Niche.app"
fi

# NICHE_ARCH=x86_64 runs both as Intel (scenario.sh). A previous release with no slice for that
# CPU (Apple silicon only, before 0.1.14) has nothing to update from there.
CPU="${NICHE_ARCH:-$(uname -m)}"
if ! lipo -archs "$PREVIOUS/Contents/MacOS/Niche" | tr ' ' '\n' | grep -qx "$CPU"; then
  echo "upgrade: skipped (the previous release has no $CPU slice: $(lipo -archs "$PREVIOUS/Contents/MacOS/Niche"))"
  exit 0
fi

for side in previous new; do
  src="$PREVIOUS"; [ "$side" = new ] && src="$NEW"
  ditto "$src" "$WORK/$side/Niche.app"
  xattr -cr "$WORK/$side/Niche.app"
  codesign --force --deep --sign - "$WORK/$side/Niche.app" 2>/dev/null
done

NICHE_PREVIOUS_APP="$WORK/previous/Niche.app" NICHE_APP="$WORK/new/Niche.app" \
  NICHE_BUDGETS="${NICHE_BUDGETS:-report}" scripts/scenario.sh upgrade
