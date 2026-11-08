#!/bin/bash
# Try the updater end to end without touching the installed Niche: builds an "old" and
# a "new" Niche, serves the new one from a local appcast on 127.0.0.1:8889 and opens the
# old one as "NicheTest" (own bundle id, own data dir, so it runs next to your Niche).
#   scripts/test-update.sh            automatic updates on: downloads, shows the banner
#   scripts/test-update.sh manual     automatic updates off: "New Niche Version Available"
#   scripts/test-update.sh idle       also restarts into the update by itself after 20 s
#                                     without mouse or keyboard input
#   scripts/test-update.sh again      reopen the old version without rebuilding
#   scripts/test-update.sh stop       quit NicheTest and stop the feed server
# Signing the update uses the "niche" key in the login keychain (see docs/release.md).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DIR="$ROOT/build/update-test"
DOMAIN=com.niche.browser.updatetest
PORT=8889
MODE="${1:-auto}"

stop() {
  pkill -f "$DIR/run/NicheTest.app/Contents/MacOS/NicheTest" 2>/dev/null || true
  [ -f "$DIR/server.pid" ] && kill "$(cat "$DIR/server.pid")" 2>/dev/null || true
  rm -f "$DIR/server.pid"
}

# A renamed copy: executable and helpers become NicheTest*, so it is its own app.
make_copy() {  # make_copy <Niche.app> <out dir> [idle seconds]
  local src="$1" out="$2" idle="${3:-}" app pb=/usr/libexec/PlistBuddy
  rm -rf "$out/NicheTest.app" && mkdir -p "$out"
  ditto "$src" "$out/NicheTest.app"
  app="$out/NicheTest.app"
  mv "$app/Contents/MacOS/Niche" "$app/Contents/MacOS/NicheTest"
  $pb -c "Set :CFBundleExecutable NicheTest" -c "Set :CFBundleIdentifier $DOMAIN" -c "Set :CFBundleName NicheTest" \
      -c "Add :LSEnvironment dict" -c "Add :LSEnvironment:NICHE_DATA_DIR string $DIR/data" \
      -c "Add :LSEnvironment:NICHE_UPDATE_FEED string http://127.0.0.1:$PORT/appcast.xml" "$app/Contents/Info.plist"
  [ -n "$idle" ] && $pb -c "Add :LSEnvironment:NICHE_UPDATE_IDLE_SECONDS string $idle" "$app/Contents/Info.plist"
  for h in "$app"/Contents/Frameworks/Niche\ Helper*.app; do
    local name new
    name="$(basename "$h" .app)"
    new="NicheTest${name#Niche}"
    mv "$h/Contents/MacOS/$name" "$h/Contents/MacOS/$new"
    $pb -c "Set :CFBundleExecutable $new" -c "Set :CFBundleName $new" "$h/Contents/Info.plist"
    mv "$h" "$app/Contents/Frameworks/$new.app"
    codesign --force --sign - --entitlements resources/NicheHelper.entitlements "$app/Contents/Frameworks/$new.app" 2>/dev/null
  done
  codesign --force --sign - --entitlements resources/Niche.entitlements "$app" 2>/dev/null
}

case "$MODE" in
  stop) stop; echo "Stopped."; exit 0 ;;
  auto|manual|idle|again) ;;
  *) echo "Usage: scripts/test-update.sh [auto|manual|idle|again|stop]" >&2; exit 1 ;;
esac

stop
sleep 1
IDLE=""
[ "$MODE" = idle ] && IDLE=20

if [ "$MODE" != again ] || [ ! -d "$DIR/old.app" ]; then
  echo "Building Niche 0.0.1 (old) and 0.0.2 (new)…"
  mkdir -p "$DIR"
  NICHE_VERSION=0.0.1 NICHE_BUILD=1000 scripts/build.sh debug > "$DIR/build.log" 2>&1
  rm -rf "$DIR/old.app" && ditto build/Niche.app "$DIR/old.app"
  NICHE_VERSION=0.0.2 NICHE_BUILD=1001 scripts/build.sh debug >> "$DIR/build.log" 2>&1
  make_copy build/Niche.app "$DIR/new"
  rm -rf "$DIR/feed" && mkdir -p "$DIR/feed"
  ditto -c -k --keepParent "$DIR/new/NicheTest.app" "$DIR/feed/Niche.zip"
  printf '<h3>Niche 0.0.2</h3><ul><li>A test update served from your Mac.</li><li>Nothing here is real.</li></ul>' > "$DIR/notes.html"
  NICHE_UPDATE_URL="http://127.0.0.1:$PORT/Niche.zip" scripts/appcast.sh "$DIR/feed/Niche.zip" "$DIR/new/NicheTest.app" "$DIR/notes.html"
fi

# Fresh state each run: the old version, onboarding done, no record of past checks.
make_copy "$DIR/old.app" "$DIR/run" "$IDLE"
rm -rf "$DIR/data" && mkdir -p "$DIR/data"
echo '{"hasSeenImportPrompt": true, "toolbarDefaultMigrated": true}' > "$DIR/data/settings.json"
defaults delete "$DOMAIN" >/dev/null 2>&1 || true
defaults write "$DOMAIN" SULastCheckTime -date "2000-01-01 00:00:00 +0000"
defaults write "$DOMAIN" SUAutomaticallyUpdate -bool "$([ "$MODE" = manual ] && echo NO || echo YES)"

python3 -I -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR/feed" > "$DIR/server.log" 2>&1 &
echo $! > "$DIR/server.pid"
sleep 1
open "$DIR/run/NicheTest.app"

cat <<EOF

NicheTest 0.0.1 is open (a separate test copy; your own Niche is untouched).
Within a few seconds it finds 0.0.2 on the local feed.
EOF
case "$MODE" in
  manual) echo "  - The sidebar shows \"New Niche Version Available\". Click it, or Niche ▸ Check for Updates…, then Download." ;;
  idle)   echo "  - The sidebar shows \"An update is ready!\". Leave the mouse and keyboard alone for 20 s: NicheTest restarts into 0.0.2 by itself." ;;
  *)      echo "  - The sidebar shows \"An update is ready!\". Click it to restart into 0.0.2, or quit NicheTest to install on quit." ;;
esac
cat <<EOF
  - After the update the sidebar says "Niche Updated!"; Niche ▸ Check for Updates… then says you're up to date.
Run again with "again" to start over from 0.0.1, and "stop" when you're done.
EOF
