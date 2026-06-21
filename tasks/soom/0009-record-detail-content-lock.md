# Record Detail Content Lock

## Goal

Lock SOOM Record Detail content behavior based on the Strava Frame Lock direction so the screen is ready for focused QA and the TestFlight QA checklist.

## Current Status

Active.

SOOM product implementation and release-readiness work are both active. This task is the top priority in `docs/ops/PROJECT_GOALS.md`.

## Acceptance Criteria

- Record Detail content structure is documented or implemented against the Strava Frame Lock direction.
- The target screens, files, and behavior under review are explicitly listed before implementation work starts.
- Content layout and interaction behavior are stable enough for focused simulator QA.
- Remaining gaps are captured as follow-up tasks instead of left implicit.
- No unrelated app code changes are included.

## Verification Method

- Compare the Record Detail behavior against the Strava Frame Lock direction.
- Run focused simulator review for the affected Record Detail path.
- Run any relevant build check if implementation code is changed.
- Capture verification evidence as screenshots, notes, changed file list, build output, or no-build rationale.

## Blockers

- None for task creation.
- Implementation may be blocked if the exact Strava Frame Lock reference, target Record Detail files, or required simulator scenario is unclear.

## Priority

1. Highest active priority.

This task comes before the SOOM TestFlight QA checklist because it defines the content behavior that QA needs to verify.
