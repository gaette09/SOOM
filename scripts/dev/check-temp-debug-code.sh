#!/usr/bin/env bash
# Fixed-path wrapper: sweeps the whole repo for leftover "TEMP batch-" debug
# markers (the convention used for throwaway verification hooks that must be
# removed before a batch is considered done — e.g. batch-3/4's synthetic
# route/heart-rate overrides). Exits non-zero if any are found, so it can
# double as a final gate before reporting a batch complete.
#
# Usage: scripts/dev/check-temp-debug-code.sh   (no arguments)

set -uo pipefail

SOOM_REPO="/Volumes/Platinum1TB/SOOM"
cd "$SOOM_REPO" || exit 1

MATCHES=$(grep -rn "TEMP batch-" --include="*.swift" SOOM SOOMTests 2>/dev/null)

if [ -n "$MATCHES" ]; then
  echo "Found leftover TEMP debug code:"
  echo "$MATCHES"
  exit 1
fi

echo "No leftover TEMP debug code found."
exit 0
