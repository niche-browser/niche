#!/bin/bash
# Stores the secrets the Release workflow signs, notarizes and publishes with on
# github.com/niche-browser/niche. Run it yourself, once, and again when the certificate or
# a password changes. Passwords are typed at hidden prompts; nothing is printed or kept.
#   scripts/setup-release-secrets.sh DeveloperID.p12
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="${NICHE_REPO:-niche-browser/niche}"

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate in the login keychain." >&2; exit 1; }
TEAM="$(sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/' <<<"$IDENTITY")"

P12="${1:-}"
if [ -z "$P12" ] || [ ! -f "$P12" ]; then
  [ -n "$P12" ] && echo "There is no file at $P12 yet."
  cat <<EOF

First export your signing certificate as a .p12 file:
  1. Open Keychain Access (it opens now).
  2. In the sidebar pick "login", then the "My Certificates" tab.
  3. Right-click "$IDENTITY" and choose Export.
  4. Save it to your Desktop as DeveloperID.p12, file format Personal Information Exchange (.p12).
  5. Choose a password for the file (you type it again below).
Then run this again:
  scripts/setup-release-secrets.sh ~/Desktop/DeveloperID.p12
EOF
  open -a "Keychain Access" 2>/dev/null || true
  exit 1
fi

echo "Signing as: $IDENTITY"
read -rsp "Password you gave $(basename "$P12"): " P12_PASSWORD; echo
read -rp "Apple ID email of the developer account: " APPLE_ID
echo "An app-specific password: account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords ▸ +"
read -rsp "App-specific password: " APPLE_APP_PASSWORD; echo

base64 -i "$P12" | gh secret set MACOS_CERTIFICATE_P12 -R "$REPO"
printf %s "$P12_PASSWORD" | gh secret set MACOS_CERTIFICATE_PASSWORD -R "$REPO"
printf %s "$IDENTITY" | gh secret set MACOS_SIGN_IDENTITY -R "$REPO"
printf %s "$APPLE_ID" | gh secret set APPLE_ID -R "$REPO"
printf %s "$TEAM" | gh secret set APPLE_TEAM_ID -R "$REPO"
printf %s "$APPLE_APP_PASSWORD" | gh secret set APPLE_APP_PASSWORD -R "$REPO"

# The private half of SUPublicEDKey (resources/Info.plist), from the login keychain.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
vendor/sparkle/bin/generate_keys --account niche -x "$TMP/key" >/dev/null
gh secret set SPARKLE_PRIVATE_KEY -R "$REPO" < "$TMP/key"

echo
gh secret list -R "$REPO"
echo
echo "Done. Delete $P12 now: GitHub has its own encrypted copy."
