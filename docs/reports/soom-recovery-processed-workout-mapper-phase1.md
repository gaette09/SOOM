# SOOM Recovery ProcessedWorkout Mapper Phase 1

Date: 2026-07-08

## Scope

Implemented the Phase 1 Recovery migration layer only. This adds a `ProcessedWorkout` to `RecoveryActivity` mapper and parity coverage against the existing `UnifiedWorkoutToRecoveryActivityMapper`.

No Recovery scoring logic, WorkoutGrowth logic, Recovery UI, Activity Detail, Share, Profile, or Record save flow was changed.

## Files Changed

- `SOOM/Features/Recovery/ProcessedWorkoutToRecoveryActivityMapper.swift`
- `SOOM/Features/UnifiedHealth/UnifiedWorkoutAnalysisInputSelector.swift`
- `SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-recovery-processed-workout-mapper-phase1.md`

## Mapper Behavior

`ProcessedWorkoutToRecoveryActivityMapper` maps normalized workout data into the existing `RecoveryActivity` input shape:

- `.running` maps to `.run`
- `.cycling` maps to `.ride`
- `.swimming` maps to `.swim`
- `.walking`, `.hiking`, `.strength`, `.yoga`, and `.other` keep the current fallback to `.run`
- duration uses rounded minutes with a minimum of `1`
- missing distance maps to `0`
- missing heart rate maps to `0`
- relative effort uses the existing MVP duration and heart-rate fallback estimate
- training load uses the existing MVP duration, heart-rate fallback, and calorie estimate
- completed date uses `ProcessedWorkout.endedAt`

The formulas intentionally match `UnifiedWorkoutToRecoveryActivityMapper` so `RecoveryCalculator` receives equivalent inputs for equivalent workouts.

## Parity Test Strategy

Added mapper tests comparing `UnifiedWorkoutToRecoveryActivityMapper` output to `ProcessedWorkoutToRecoveryActivityMapper` output after building `ProcessedWorkout` from the same `UnifiedWorkout`.

Covered cases:

- cycling workout
- running workout
- walking workout
- time-only workout
- missing heart rate
- route-backed workout with source distance
- route-backed workout with missing source distance
- processed selector filtering of excluded workouts

The route-backed missing source distance case intentionally documents the only Phase 1 difference: `ProcessedWorkoutBuilder` can derive distance from route data, while the direct UnifiedWorkout mapper maps missing source distance to `0`.

## Unchanged RecoveryCalculator Note

`RecoveryCalculator` was not edited. This patch adds an adapter layer only, preserving current recovery score, readiness, recommendation, and trend behavior.

`WorkoutGrowth` mappers/builders were not edited.

## Missing Data Behavior

The processed mapper keeps current recovery fallbacks:

- no distance: `0 km`
- no heart rate: visible recovery input heart rate `0`, with the existing scoring estimate fallback of `120 bpm`
- no calories: `0` contribution to training load
- zero/negative duration normalized by `ProcessedWorkoutBuilder`, then recovered as at least `1` minute for calculator input

## Next Recommended Phase

Move Recovery preview/provider mapping to call `ProcessedWorkoutBuilder` plus `ProcessedWorkoutToRecoveryActivityMapper`, then compare `RecoveryCalculator` summary output against the current UnifiedWorkout path before replacing any production-facing Recovery source.

## Verification

- Focused test attempted:
  `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests`
- Focused test result: blocked by CoreSimulator infrastructure after build/link warnings only. Error: failed to clone device named `iPhone 17e`; device was allocated but stuck in creation state.
- Generic simulator build passed:
  `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- `git diff --check`: passed
- `git status --short`: only intended mapper, selector, test, project, and report changes before commit
