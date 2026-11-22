#!/bin/bash
# Puts Niche's patches (scripts/cef-patches) on a Chromium checkout, in order, for build-cef.sh and
# rebuild-cef.sh.
#   scripts/cef-patches-apply.sh <chromium/src>          the current patches on (nothing if they already are)
#   scripts/cef-patches-apply.sh <chromium/src> --off    every Niche patch off
#
# The versions it put on are kept in <src>/.niche-applied-patches, because two patches can touch one
# file (safe-downloads.patch goes over downloads-without-cef-browser.patch) and a changed patch no
# longer reverses itself: the kept copies come off newest first, then the current ones go on. A
# patch that doesn't apply puts the previous set back and stops, so the checkout is never half
# patched. Only the patches from the first one that changed come off and go back on, so ninja
# rebuilds only what they touch.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
SRC="${1:?usage: scripts/cef-patches-apply.sh <chromium/src> [--off]}"
PATCHES="$PWD/scripts/cef-patches"
APPLIED="$SRC/.niche-applied-patches"

off() {  # $1: a folder of patches that are on
  for p in $(ls -r "$1"/*.patch 2>/dev/null); do
    if git -C "$SRC" apply --check --reverse "$p" 2>/dev/null; then
      git -C "$SRC" apply --reverse "$p"
    fi
  done
}
on() {  # $1: a folder of patches to put on; returns 1 at the first that doesn't apply, after taking the rest off
  local done=()
  for p in "$1"/*.patch; do
    if ! git -C "$SRC" apply --check "$p" 2>/dev/null; then
      echo "$(basename "$p") does not apply" >&2
      for d in $(printf '%s\n' "${done[@]:-}" | sed '/^$/d' | tail -r); do git -C "$SRC" apply --reverse "$d"; done
      return 1
    fi
    git -C "$SRC" apply "$p"
    done+=("$p")
  done
}

if [ "${2:-}" = --off ]; then
  # Without a record (a checkout from before it was kept), the current files are the best guess.
  off "$([ -d "$APPLIED" ] && echo "$APPLIED" || echo "$PATCHES")"
  rm -rf "$APPLIED"
  echo "Niche's patches are off"
  exit 0
fi
if [ -d "$APPLIED" ] && diff -rq "$APPLIED" "$PATCHES" >/dev/null 2>&1; then
  echo "Niche's patches are on and unchanged"
  exit 0
fi
PREVIOUS="$([ -d "$APPLIED" ] && echo "$APPLIED" || echo "$PATCHES")"
# The patches before the first difference (in name order, by name and content) stay on.
KEEP=""
if [ -d "$APPLIED" ]; then
  for n in $( (ls "$APPLIED"; ls "$PATCHES") | grep '\.patch$' | LC_ALL=C sort -u); do
    [ -f "$APPLIED/$n" ] && [ -f "$PATCHES/$n" ] && cmp -s "$APPLIED/$n" "$PATCHES/$n" || break
    KEEP="$n"
  done
fi
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/old" "$STAGE/new"
for p in "$PREVIOUS"/*.patch; do [[ "$(basename "$p")" > "$KEEP" ]] && cp "$p" "$STAGE/old/"; done
for p in "$PATCHES"/*.patch; do [[ "$(basename "$p")" > "$KEEP" ]] && cp "$p" "$STAGE/new/"; done
off "$STAGE/old"
if ! on "$STAGE/new"; then
  [ "$PREVIOUS" = "$PATCHES" ] || on "$STAGE/old" || true
  exit 1
fi
rm -rf "$APPLIED"
cp -R "$PATCHES" "$APPLIED"
echo "Applied $(ls "$PATCHES"/*.patch | wc -l | tr -d ' ') patches"
