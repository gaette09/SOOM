#!/usr/bin/env bash
# Fixed-path wrapper around SOOM-OS's verify-build-and-refresh.sh, so the Bash
# permission pattern for build verification stays identical across calls —
# no per-call log filename, no inline variables. Captures full output to a
# fixed log path (overwritten each run) and prints only a short summary.
#
# Usage: scripts/dev/verify-and-check.sh   (no arguments)

set -uo pipefail

SOOM_OS_REPO="/Volumes/Platinum1TB/SOOM-OS"
LOG_FILE="/tmp/soom-build.log"

cd "$SOOM_OS_REPO" || exit 1
bash scripts/usage/verify-build-and-refresh.sh > "$LOG_FILE" 2>&1
STATUS=$?

echo "---- last 25 lines of $LOG_FILE ----"
tail -25 "$LOG_FILE"
echo "-------------------------------------"

if grep -q "BUILD SUCCEEDED" "$LOG_FILE"; then
  echo "RESULT: BUILD SUCCEEDED"
else
  echo "RESULT: BUILD FAILED -- full output at $LOG_FILE"
fi

exit "$STATUS"
