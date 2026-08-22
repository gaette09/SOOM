#!/usr/bin/env bash
# Fixed-path wrapper: runs one or more XCTest classes against the isolated
# SOOM-Verify simulator (never the shared "iPhone 17" device other sessions
# may be using) with -parallel-testing-enabled NO, which avoids the "Failed
# to clone device ... stuck in creation state" error that xcodebuild's
# parallel-test device cloning triggers in this environment. Captures full
# output to a fixed log path (overwritten each run) and prints only a short
# summary, so the Bash permission pattern stays identical across calls.
#
# Usage: scripts/dev/run-tests.sh <TestClass1> [TestClass2] [TestClass3] ...
#   e.g. scripts/dev/run-tests.sh FitnessTrendCalculatorTests FitnessTrendBuilderTests

set -uo pipefail

SOOM_REPO="/Volumes/Platinum1TB/SOOM"
cd "$SOOM_REPO" || exit 1

VERIFY_SIM_UDID="2E232F77-E7A0-4233-A7AC-49538411AC24"
LOG_FILE="/tmp/soom-run-tests.log"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <TestClass1> [TestClass2] [TestClass3] ..."
  exit 1
fi

ONLY_TESTING_ARGS=()
for class in "$@"; do
  ONLY_TESTING_ARGS+=("-only-testing:SOOMTests/$class")
done

xcodebuild test \
  -project SOOM.xcodeproj \
  -scheme SOOM \
  -destination "platform=iOS Simulator,id=$VERIFY_SIM_UDID" \
  -parallel-testing-enabled NO \
  "${ONLY_TESTING_ARGS[@]}" \
  > "$LOG_FILE" 2>&1
STATUS=$?

echo "---- test results ----"
grep -E "Test Case|Test Suite .* (passed|failed)|\*\* TEST" "$LOG_FILE" | tail -80
echo "-----------------------"

if grep -q "TEST SUCCEEDED" "$LOG_FILE"; then
  echo "RESULT: TEST SUCCEEDED"
else
  echo "RESULT: TEST FAILED -- full output at $LOG_FILE"
fi

exit "$STATUS"
