#!/usr/bin/env bash
# Fixed-path wrapper: runs the read-only checks used on 2026-08-24 to
# diagnose two failure modes seen together on this machine —
#   (a) /Volumes/Platinum1TB going EPERM for Bash/Read mid-session (TCC
#       "Files and Folders" access to the external volume silently revoked,
#       likely after a remount), and
#   (b) `xcodebuild test` failing with "Failed to clone device ... stuck in
#       creation state" because CoreSimulatorService can't write to
#       XCTestDevices under that same external volume.
# Prints OK/FAIL per check plus a plain-language next step. No arguments,
# so the Bash permission pattern stays identical across calls.
#
# Usage: scripts/dev/diagnose-disk-issue.sh          (diagnose only)
#        scripts/dev/diagnose-disk-issue.sh --fix     (diagnose, then offer
#                                                       the CoreSimulator
#                                                       restart if needed)
#
# WARNING about --fix: restarting CoreSimulatorService kills EVERY booted
# simulator, not just SOOM-Verify — including any simulator session the
# user has open for unrelated work. This happened by accident during the
# 2026-08-24 diagnosis (their booted "iPhone 17 Pro" session was silently
# shut down). --fix always asks for confirmation before doing this; there
# is no non-interactive way to skip that prompt.

set -uo pipefail

VOLUME="/Volumes/Platinum1TB"
SOOM_REPO="$VOLUME/SOOM"
SOOM_OS_REPO="$VOLUME/SOOM-OS"
XCTEST_DEVICES_DIR="$VOLUME/Developer/Xcode/XCTestDevices"

FAILS=0

pass() { echo "  OK   $1"; }
fail() { echo "  FAIL $1"; FAILS=$((FAILS + 1)); }

echo "== 1. Volume mount status =="
if mount | grep -q "on $VOLUME "; then
  pass "$VOLUME is mounted"
  diskutil info "$VOLUME" 2>/dev/null | grep -E "Protocol|Removable Media|Owners" | sed 's/^/       /'
else
  fail "$VOLUME is not mounted at all"
fi

echo "== 2. Bash read/write access to the volume =="
if (cd "$SOOM_REPO" 2>/dev/null && git status >/dev/null 2>&1); then
  pass "git status works in $SOOM_REPO"
else
  fail "git status failed in $SOOM_REPO (EPERM or not a repo — this is the 'disk access revoked' symptom)"
fi
if (cd "$SOOM_OS_REPO" 2>/dev/null && git status >/dev/null 2>&1); then
  pass "git status works in $SOOM_OS_REPO"
else
  fail "git status failed in $SOOM_OS_REPO"
fi

echo "== 3. XCTestDevices write access (what CoreSimulatorService needs for 'xcodebuild test' cloning) =="
if [ -d "$XCTEST_DEVICES_DIR" ]; then
  TEST_FILE="$XCTEST_DEVICES_DIR/.diagnose-disk-issue-write-test"
  if touch "$TEST_FILE" 2>/dev/null; then
    rm -f "$TEST_FILE"
    pass "shell can write to $XCTEST_DEVICES_DIR"
    echo "       (this only proves the shell can write — CoreSimulatorService is a"
    echo "        separate daemon and can still fail here with its own TCC grant;"
    echo "        if 'xcodebuild test' still hits 'stuck in creation state', use"
    echo "        scripts/dev/run-tests.sh, which passes -parallel-testing-enabled NO"
    echo "        and avoids the clone entirely — no CoreSimulator restart needed.)"
  else
    fail "shell cannot write to $XCTEST_DEVICES_DIR"
  fi
else
  echo "  --   $XCTEST_DEVICES_DIR does not exist (nothing to check yet)"
fi

echo "== 4. CoreSimulator daemon status =="
launchctl list 2>/dev/null | grep -i coresimulator | sed 's/^/       /'
if launchctl list 2>/dev/null | grep -q "com.apple.CoreSimulator.CoreSimulatorService"; then
  pass "CoreSimulatorService is registered with launchd"
else
  fail "CoreSimulatorService is not running"
fi

echo "== 5. Booted simulators / open Simulator.app windows =="
xcrun simctl list devices 2>/dev/null | grep -i Booted | sed 's/^/       /' || echo "       (none booted)"
osascript -e 'tell application "System Events" to tell process "Simulator" to get name of every window' 2>/dev/null | sed 's/^/       windows: /' || echo "       Simulator.app is not running"

echo "== 6. Recent CoreSimulator.log permission errors (last 10 min) =="
LOG_FILE="$HOME/Library/Logs/CoreSimulator/CoreSimulator.log"
if [ -f "$LOG_FILE" ]; then
  RECENT_ERRORS=$(tail -500 "$LOG_FILE" | grep -i "not permitted\|stuck in creation")
  if [ -n "$RECENT_ERRORS" ]; then
    echo "$RECENT_ERRORS" | tail -10 | sed 's/^/       /'
  else
    echo "       none found in the last 500 lines"
  fi
else
  echo "       $LOG_FILE not found"
fi

echo "== 7. Disk space =="
df -h "$VOLUME" / 2>/dev/null | sed 's/^/       /'

echo
if [ "$FAILS" -eq 0 ]; then
  echo "All checks passed. If 'xcodebuild test' still fails to clone a device,"
  echo "use scripts/dev/run-tests.sh instead of a raw xcodebuild test call."
  exit 0
fi

echo "$FAILS check(s) failed."
echo "Next step: System Settings -> Privacy & Security -> Files and Folders"
echo "(or Full Disk Access) -- re-grant access to $VOLUME for the terminal app"
echo "hosting this session, then re-run this script."

if [ "${1:-}" = "--fix" ]; then
  echo
  echo "--fix: this can also restart CoreSimulatorService, which force-shuts-down"
  echo "EVERY booted simulator (not just SOOM-Verify)."
  read -r -p "Restart CoreSimulatorService now? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    osascript -e 'quit app "Simulator"' 2>/dev/null
    sleep 1
    killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null
    echo "Sent restart signal. Re-run this script (without --fix) to confirm it helped."
  else
    echo "Skipped."
  fi
fi

exit 1
