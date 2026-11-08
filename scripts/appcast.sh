#!/bin/bash
# Writes build/dist/appcast.xml, the Sparkle feed installed copies of Niche check every
# 8 hours (SUFeedURL: releases/latest/download/appcast.xml). The update archive is
# signed with the EdDSA key: SPARKLE_PRIVATE_KEY (CI secret), or the "niche" key in the
# login keychain (made once with vendor/sparkle/bin/generate_keys --account niche).
#   scripts/appcast.sh [Niche.zip] [Niche.app] [release-notes.html]
# NICHE_UPDATE_URL overrides the download URL (tests point it at a local server).
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP="${1:-build/dist/Niche.zip}"
APP="${2:-build/Niche.app}"
NOTES="${3:-}"
OUT="$(dirname "$ZIP")/appcast.xml"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
MIN_OS="$(plist LSMinimumSystemVersion)"
URL="${NICHE_UPDATE_URL:-https://github.com/niche-browser/niche/releases/download/v$VERSION/Niche.zip}"

SIGN=vendor/sparkle/bin/sign_update
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  ENCLOSURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - "$ZIP")"
else
  ENCLOSURE="$("$SIGN" --account niche "$ZIP")"
fi

DESCRIPTION=""
if [ -n "$NOTES" ] && [ -f "$NOTES" ]; then
  DESCRIPTION="
      <description><![CDATA[$(cat "$NOTES")]]></description>"
fi

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Niche</title>
    <link>https://github.com/niche-browser/niche/releases</link>
    <item>
      <title>Niche $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/niche-browser/niche/releases</sparkle:fullReleaseNotesLink>$DESCRIPTION
      <enclosure url="$URL" type="application/octet-stream" $ENCLOSURE/>
    </item>
  </channel>
</rss>
XML
echo "Wrote $OUT (Niche $VERSION, build $BUILD)"
