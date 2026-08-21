#!/usr/bin/env bash
# Fixed-path wrapper: terminate -> install -> launch SOOM on the "iPhone 17"
# simulator. Resolves the built .app path and the simulator UDID at runtime
# (boots the simulator if it isn't already), so this script never needs
# arguments and the Bash permission pattern stays identical across calls.
#
# Usage: scripts/dev/reinstall-and-launch.sh   (no arguments)

set -uo pipefail

BUNDLE_ID="app.soom.prototype"
DEVICE_NAME="iPhone 17"
DERIVED_DATA_ROOT="$HOME/Library/Developer/Xcode/DerivedData"

APP_PATH=$(ls -td "$DERIVED_DATA_ROOT"/SOOM-*/Build/Products/Debug-iphonesimulator/SOOM.app 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: no built SOOM.app found under DerivedData. Run scripts/dev/verify-and-check.sh first."
  exit 1
fi

UDID=$(xcrun simctl list devices | grep "$DEVICE_NAME (" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
if [ -z "$UDID" ]; then
  echo "ERROR: no simulator device named exactly '$DEVICE_NAME' found."
  exit 1
fi

if ! xcrun simctl list devices | grep -q "$UDID.*Booted"; then
  echo "Booting $DEVICE_NAME ($UDID)..."
  xcrun simctl boot "$UDID"
  open -a Simulator
  sleep 4
fi

xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "Launched $BUNDLE_ID on $DEVICE_NAME ($UDID)"
echo "From: $APP_PATH"
