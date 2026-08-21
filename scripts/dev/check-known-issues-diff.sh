#!/usr/bin/env bash
# Fixed-path wrapper: shows the diff for docs/SOOM_KNOWN_ISSUES.md against the
# last commit, from a stable cwd. Run after editing the known-issues doc at
# the end of a batch, to confirm the entry looks right before moving on.
#
# Usage: scripts/dev/check-known-issues-diff.sh   (no arguments)

set -uo pipefail

SOOM_REPO="/Volumes/Platinum1TB/SOOM"
cd "$SOOM_REPO" || exit 1

git diff -- docs/SOOM_KNOWN_ISSUES.md
