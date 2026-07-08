# SOOM HealthKit Read Phase 1B Duplicate Source Priority

Date: 2026-07-08

## Summary

Implemented HealthKit Read Phase 1B duplicate/source-priority guardrails for manual HealthKit workout import.

The import path remains:

`HealthKitWorkout -> UnifiedWorkout -> UnifiedWorkoutStore -> ProcessedWorkoutBuilder`

This phase adds a conservative non-destructive skip guard so a HealthKit workout is not imported when it appears to duplicate an existing SOOM local workout. No records are deleted or merged.

## Files Changed

- `SOOM/Features/HealthKit/HealthKitWorkoutImportPipeline.swift`
- `SOOMTests/HealthKitWorkoutImportPipelineTests.swift`
- `docs/reports/soom-healthkit-read-phase1b-duplicate-source-priority.md`

## Duplicate Strategy

Existing exact duplicate guard remains intact:

- `SwiftDataUnifiedWorkoutStore` still upserts by `externalId + source`.
- Reimporting the same Apple Health workout updates the existing `.appleHealthKit` record instead of creating another record.

New Phase 1B cross-source guard:

- During manual HealthKit import, the pipeline fetches existing recent workouts from `UnifiedWorkoutStore`.
- If an incoming `.appleHealthKit` workout conservatively matches an existing `.soomLocal` workout, the HealthKit workout is skipped.
- Skipped HealthKit workouts are not saved and route persistence is not attempted for them.
- The import result reflects skipped count through the existing `HealthKitWorkoutImportResult.success` count behavior.

## Source Priority Rules

Priority for import-time duplicate guardrails:

1. Keep existing SOOM local workout.
2. Skip similar Apple HealthKit import if it appears to represent the same session.
3. Import Apple HealthKit workout when no conservative SOOM local duplicate exists.

Reasoning:

- SOOM local workouts preserve SOOM-specific record intent, route capture, share flow, and local-first session state.
- HealthKit workouts are valuable for Apple Watch and historical workouts, but should not create visible duplicates for sessions already recorded in SOOM.

## Conservative Matching Rules

A HealthKit import is skipped only when an existing workout satisfies all of these:

- Existing source is `.soomLocal`.
- Imported source is `.appleHealthKit`.
- Workout type is the same.
- Start times are within 5 minutes.
- End times are within 5 minutes.
- Duration differs by no more than 5%.
- Both distances exist and differ by no more than 10%.

Conservative exclusions:

- Different start/end time imports are not skipped.
- Same day but different sport imports are not skipped.
- Missing distance on either side is not enough to skip.
- No automatic merge or destructive delete is performed.

## Limitations

- The duplicate guard is import-time only; it does not yet provide a library review UI.
- It only guards SOOM local vs Apple HealthKit duplicates.
- It does not handle Garmin/Samsung/Google because those integrations remain deferred.
- It does not mark skipped workouts with a persisted link to the local workout.
- It uses a broad local lookback window against `UnifiedWorkoutStore`; future work can make this window explicit in configuration or query by date range.
- Missing-distance duplicates can still import to avoid hiding distinct sessions with weak evidence.

## Tests Added

Focused tests cover:

- Exact HealthKit `externalId + source` upsert still does not duplicate.
- Similar SOOM local vs HealthKit workout prefers local and skips import.
- Different-time HealthKit workout still imports.
- Same-day different-sport HealthKit workout still imports.
- Missing distance does not cause unsafe skip.
- HealthKit-only workout still imports.
- Imported HealthKit-only workout remains compatible with `ProcessedWorkoutBuilder`.

## Verification

Focused test command attempted:

```sh
xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests -only-testing:SOOMTests/UnifiedWorkoutDeduplicationEngineTests -only-testing:SOOMTests/ProcessedWorkoutBuilderTests -quiet
```

Result:

- Test build reached test startup.
- Execution was blocked by CoreSimulator infrastructure:
  - `Failed to clone device named 'iPhone 17 Pro'.`
  - Device was allocated but stuck in creation state.
- No test assertion failure was reported before the simulator clone failure.

Requested build command:

```sh
xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.

## Next Recommended Phase

Phase 1C: route-safe import.

Recommended work:

- Keep route persistence optional.
- Confirm route fetch and route persistence failures never block workout summary import.
- Keep route-derived distance/elevation flowing through `ProcessedWorkoutBuilder`.
- Continue deferring route smoothing, snapping, matching, and sampled stream persistence.
