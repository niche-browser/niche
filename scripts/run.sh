#!/bin/bash
# Build (if needed) and launch Niche. Pass --rebuild to force a build.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--rebuild" ] || [ ! -d build/Niche.app ]; then scripts/build.sh "${2:-release}"; fi
env -u ELECTRON_RUN_AS_NODE open -n build/Niche.app --args "${@:3}"
