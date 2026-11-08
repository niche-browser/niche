#!/bin/bash
# Installs or updates Niche from the latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/niche-browser/niche/main/scripts/install.sh | bash
# Files downloaded with curl carry no quarantine flag, so macOS opens the
# unnotarized build without the Gatekeeper prompt a browser download triggers.
# Overrides: NICHE_DOWNLOAD_URL (zip to install), NICHE_INSTALL_DIR, NICHE_NO_OPEN=1.
set -euo pipefail

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Everything runs from main so a partially downloaded script never executes.
main() {
  local url="${NICHE_DOWNLOAD_URL:-https://github.com/niche-browser/niche/releases/latest/download/Niche.zip}"
  local dir="${NICHE_INSTALL_DIR:-}"

  [ "$(uname -s)" = Darwin ] || fail "Niche runs on macOS only."
  [ "$(uname -m)" = arm64 ] || fail "Niche needs a Mac with Apple silicon (M1 or later)."
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "Niche needs macOS 14 Sonoma or later."

  if [ -z "$dir" ]; then
    if [ -w /Applications ]; then dir=/Applications; else dir="$HOME/Applications"; fi
  fi
  mkdir -p "$dir"

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  say "Downloading Niche…"
  curl -fL --progress-bar -o "$TMP/Niche.zip" "$url" || fail "The download failed. Check your connection and run the command again."
  ditto -x -k "$TMP/Niche.zip" "$TMP" || fail "The download was damaged. Run the command again."
  [ -d "$TMP/Niche.app" ] || fail "The download did not contain Niche.app."

  if pgrep -xq Niche; then
    say "Quitting Niche to update it…"
    osascript -e 'quit app "Niche"' >/dev/null 2>&1 || true
    for _ in $(seq 20); do pgrep -xq Niche || break; sleep 0.5; done
    pgrep -xq Niche && fail "Niche is still running. Quit it and run the command again."
  fi

  rm -rf "$dir/Niche.app"
  mv "$TMP/Niche.app" "$dir/"
  xattr -dr com.apple.quarantine "$dir/Niche.app" 2>/dev/null || true

  say "Niche is installed in $dir. Run this command again any time to update."
  [ -n "${NICHE_NO_OPEN:-}" ] || open "$dir/Niche.app"
}

main "$@"
