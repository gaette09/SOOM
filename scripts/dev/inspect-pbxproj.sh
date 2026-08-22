#!/usr/bin/env bash
# Fixed-path wrapper: greps project.pbxproj with 5 lines of context on each
# side, so looking up an existing file's registration (to copy its 4-site
# PBXBuildFile/PBXFileReference/group/Sources pattern for a new file) is one
# command with one argument instead of picking different line-number windows
# each time.
#
# Usage: scripts/dev/inspect-pbxproj.sh <search-term>
#   e.g. scripts/dev/inspect-pbxproj.sh RelativeEffortComparison.swift

set -uo pipefail

SOOM_REPO="/Volumes/Platinum1TB/SOOM"
cd "$SOOM_REPO" || exit 1

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <search-term>"
  exit 1
fi

grep -n -B5 -A5 -- "$1" SOOM.xcodeproj/project.pbxproj
