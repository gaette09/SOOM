#!/usr/bin/env bash
# Fixed-path wrapper: checks whether one or more pbxproj object IDs (this
# project's custom 6-hex-digit scheme, e.g. 0205FC for a PBXFileReference or
# 01060A for its PBXBuildFile counterpart) are already in use, so IDs for a
# newly-registered Swift file can be picked without collisions. Replaces the
# ad hoc grep-into-sort-uniq-then-for-loop combo used before this existed.
#
# Usage: scripts/dev/check-pbxproj-id.sh <ID1> [ID2] [ID3] ...
#   e.g. scripts/dev/check-pbxproj-id.sh 02060C 02060D 02060E
#
# Exits 1 if any of the given IDs are already taken.

set -uo pipefail

SOOM_REPO="/Volumes/Platinum1TB/SOOM"
cd "$SOOM_REPO" || exit 1

PBXPROJ="SOOM.xcodeproj/project.pbxproj"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <ID1> [ID2] [ID3] ..."
  exit 1
fi

STATUS=0
for id in "$@"; do
  COUNT=$(grep -Fo -- "$id" "$PBXPROJ" | wc -l | tr -d ' ')
  if [ "$COUNT" -gt 0 ]; then
    echo "$id TAKEN ($COUNT occurrence(s))"
    STATUS=1
  else
    echo "$id free"
  fi
done

exit "$STATUS"
