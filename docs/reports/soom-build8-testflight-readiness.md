# SOOM Build 8 TestFlight Readiness Review

Date: 2026-07-08

## Scope

Final readiness review before preparing SOOM Build 8 for TestFlight.

This review does not bump the build number and does not upload TestFlight.

## Current QA Result

Physical device broad-flow QA passed:

- Record: PASS
- Activity Detail: PASS
- Share: PASS
- Profile: PASS
- Recovery: PASS
- Crash: none observed

Fine UI/UX polish is intentionally deferred.

## Commits Included Since Build 7

Build 7 baseline:

- `3687954 chore(release): bump soom build to 7`

Build 8 implementation and verification commits reviewed:

- `48163c1 docs(qa): add build 8 activity detail implementation plan`
- `29d0ded feat(activity): refine workout detail hierarchy`
- `0ee831b docs(qa): add build 8 activity detail qa report`
- `b9d60c9 docs(qa): add build 8 device qa checklist`
- `5bd5cc4 fix(activity): polish route share and detail sheet behavior`
- `f94e657 fix(activity): fit workout route to visible map area`
- `74dc878 fix(share): isolate card preview layout`
- `623d73d fix(share): improve story card typography`
- `7811404 fix(share): simplify transparent story sharing`
- `cd0646d fix(share): preserve transparent metric export`
- `97d735a fix(share): refine transparent export layouts`
- `463a5f8 fix(share): vary transparent card layouts`
- `bf5bdc1 fix(share): refine transparent card variants`
- `049ce60 fix(share): implement transparent card v2 layouts`
- `53029e7 feat(record): add compact active workout hud`
- `8c011f5 docs(qa): add record active hud device qa checklist`
- `d368749 docs(data): add soom data pipeline v1 audit`
- `e7f6477 docs(data): plan processed workout read model`
- `d9f2435 feat(data): add processed workout read model`
- `1254a63 feat(activity): use processed workout metrics`
- `f10c104 feat(share): use processed workout metrics`
- `9160a54 feat(profile): use processed workout aggregation`
- `fe391d9 docs(data): audit recovery processed workout migration`
- `bc7dfea feat(recovery): map processed workouts to recovery activity`
- `f695ecf docs(data): plan recovery processed workout parity`
- `a96d171 test(recovery): add processed workout parity coverage`
- `baa5d2b docs(data): plan recovery provider processed workout migration`
- `105f321 feat(recovery): use processed workouts in preview provider`
- `4128ee9 docs(qa): add recovery processed workout device qa checklist`
- `7a9736c docs(data): audit record saved workout normalization`
- `9d7dcf8 test(data): cover record processed workout mapping`
- `1ee72f3 test(data): cover record saver processed workout flow`

## Major Changes

### Activity Detail Refinement

- Refined Activity Detail hierarchy while preserving Build 7 Mapbox style behavior.
- Added conservative one-line SOOM rhythm insight behavior.
- Cleaned up the core stat tile presentation.
- Preserved no-route fallback behavior.

### Route Fitting

- Improved Activity Detail route fitting on first presentation.
- Adjusted visible-area route centering when the detail sheet moves to the bottom snap state.
- Preserved Mapbox style URI and Record map behavior.

### Share Transparent Cards

- Reworked Share composer toward transparent story-card sharing.
- Removed background selection from the share flow.
- Fixed carousel overlap and export/save clipping issues.
- Preserved transparent PNG export by separating preview checkerboard/dark contrast from export content.
- Added save confirmation before writing to Photos.

### Record Compact HUD

- Added compact active workout HUD as the default active state.
- Preserved full HUD through expand/collapse behavior.
- Kept existing sport-specific metric grid in expanded mode.
- Preserved save flow, heading follow/navigation cone behavior, and hidden route recommendation.

### ProcessedWorkout Data Pipeline

- Added `ProcessedWorkout` / display snapshot read-model layer.
- Added builder coverage for cycling, running, walking, time-only, route-backed, and missing-metric states.
- Added Record-shaped fixture coverage for ProcessedWorkout behavior.

### Activity, Share, Profile, Recovery Preview Data Migration

- Activity Detail now reads display metrics through ProcessedWorkout where safe.
- Share card model building now uses ProcessedWorkout-derived metrics while preserving transparent card layouts.
- Profile aggregation now uses ProcessedWorkout-derived values where safe.
- Recovery preview provider now uses ProcessedWorkout internally.
- RecoveryCalculator, WorkoutGrowth, production Recovery source, and Recovery UI remain unchanged.

### Record Saver To ProcessedWorkout Coverage

- Added end-to-end persistence coverage that saves through `RecordWorkoutSaver`, fetches persisted workout and route values, then builds ProcessedWorkout.
- Covered route-backed cycling/running/walking, time-only saves, and location-denied saves.
- No production persistence fixes were required.

## Build Status

Latest documented verification:

- `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed
- `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`: passed

No build-number bump has been performed for Build 8 yet.

## Simulator Test Limitation

Focused simulator test execution remains limited by CoreSimulator infrastructure:

- Affected command pattern:
  `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' ...`
- Observed failure:
  CoreSimulator failed to clone the requested simulator device and left it stuck in creation state.

This is not currently treated as an app/test failure because compile/build-for-testing and generic simulator builds pass, and the failure occurs at simulator provisioning.

## Physical Device QA Result

User-reported broad-flow physical device QA passed:

- Record flow, including compact HUD: PASS
- Activity Detail flow, including route fitting: PASS
- Share flow, including current transparent card behavior: PASS
- Profile aggregation/display: PASS
- Recovery flow: PASS
- App crash check: none observed

This satisfies the readiness checklist decision rule for moving to TestFlight preparation.

## Known Deferred Items

Deferred by product decision:

- Fine Share card visual polish.
- Fine Activity Detail visual polish.
- Advanced chart redesign.
- New recovery scoring or training load model.
- Production Recovery provider migration to saved workouts.
- Garmin, Samsung, Google direct integrations.
- Full HealthKit write support.
- Advanced GPS smoothing, route snapping, and sampled-stream persistence.

Known data limitations:

- Record saves do not yet capture heart rate, cadence, calories, elevation, power, pause-adjusted moving time, splits, zones, or sampled streams.
- Current local Record workouts remain partial by design.
- Production Recovery source is intentionally unchanged; only the preview provider uses ProcessedWorkout.

## Release Risk Notes

| Risk | Status | Release Impact |
| --- | --- | --- |
| CoreSimulator cannot execute focused tests reliably. | Known infrastructure issue. | Does not block TestFlight if build and physical QA remain clean. |
| Share card design still has deferred polish. | Accepted by user. | Does not block Build 8 broad-flow release. |
| Record local data is partial. | Covered by ProcessedWorkout missing-data rules and tests. | Acceptable for Build 8; should inform future data pipeline work. |
| Recovery production source not migrated. | Intentional. | Low risk because production Recovery behavior remains unchanged. |
| ProcessedWorkout adoption changed multiple surfaces. | Covered by targeted tests/builds and broad-flow device QA. | Acceptable pending final build bump/upload verification. |

## Final Recommendation

Build 8 is ready to prepare for TestFlight.

Proceed with the next release task:

1. Bump the build number for Build 8.
2. Run the normal archive/build verification.
3. Upload to TestFlight.

Do not create another Build 8 patch unless a new blocking issue appears during build bump, archive, upload, or final device smoke testing.

## Verification

- Documentation-only change.
- No app code modified.
- No build number bumped.
- No TestFlight upload performed.
- `git diff --check`: passed.
- `git status --short`: only this new readiness report before commit.
