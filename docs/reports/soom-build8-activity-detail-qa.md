# SOOM Build 8 Activity Detail QA Verification

Date: 2026-06-26

Commit under test: `29d0ded feat(activity): refine workout detail hierarchy`

Status: ready for device QA; simulator test execution is blocked by CoreSimulator infrastructure

## Scope

QA target:

- Build 8 Activity Detail focused UI refinement.
- Verify as much as possible before a TestFlight decision.

Rules followed:

- No app code was changed.
- No Mapbox style URI was changed.
- Record, Feed, and Share flows were not modified.
- TestFlight was not uploaded.

## Simulator Destinations

Command:

```text
xcrun simctl list devices available
```

Available iPhone simulator destinations observed:

- iOS 26.4 `iPhone 17 Pro` `B5E2FFBE-D302-4791-88F0-BE0B077045EA`
- iOS 26.5 `iPhone 17 Pro` `E6A13169-3246-423B-895D-A707A36D5076`
- iOS 26.5 `iPhone 17 Pro Max` `A9E506E8-EE72-4A99-BD34-D5D2239B3D8B`
- iOS 26.5 `iPhone 17e` `6916764A-5446-4174-991F-B3AF360CBF99`
- iOS 26.5 `iPhone Air` `6F34A22F-7DB2-4684-BE5F-7B869D05223D`
- iOS 26.5 `iPhone 17` `EA2F4FAE-2E66-42E4-ABA8-73109D60FFD3`

Stable non-17 Pro candidate selected for retry:

- iOS 26.5 `iPhone 17e`

## Build Result

Command:

```text
xcodebuild build -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'
```

Result:

- Passed.
- Final result: `** BUILD SUCCEEDED **`

This confirms the app target compiles after the Build 8 Activity Detail implementation.

## Targeted Test Result

Targeted test command attempted on non-17 Pro simulator:

```text
xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests
```

Result:

- Failed before test execution.
- The app and test target build steps progressed, but Xcode could not start the test session because CoreSimulator failed to clone the selected simulator.

CoreSimulator error:

```text
Test target SOOMTests encountered an error
Failed to clone device named 'iPhone 17e'.
Underlying Error: The operation couldn't be completed.
Device was allocated but was stuck in creation state.
Check CoreSimulator.log for more information.
```

Previous known issue from the implementation run:

- The same failure mode occurred on `iPhone 17 Pro`.
- Error: `Failed to clone device named 'iPhone 17 Pro'`.

Assessment:

- This is a simulator infrastructure issue.
- It is not currently evidence of an app compile failure, test assertion failure, app crash, or Build 8 Activity Detail regression.
- The focused tests should be re-run after CoreSimulator is reset or a working simulator runtime/device is available.

## Manual Device QA Checklist

Run this on a physical device or a healthy simulator before TestFlight approval:

- Activity Detail opens from Home, Feed, and unified workout library entry points.
- Routed workout detail opens in the map sheet without navigation regressions.
- No-route workout detail opens in standalone detail and the fallback hero reads coherently.
- Build 7 Mapbox style still appears on route/detail maps.
- Record map behavior is unchanged.
- One-line rhythm insight appears near the top of Activity Detail.
- The rhythm insight is calm, recovery-first, and not repeated as stacked AI cards.
- Four core stat tiles display correctly:
  - distance,
  - duration,
  - average pace or speed,
  - recovery impact, heart-rate fallback, or neutral pending state.
- Stat tile labels, values, and spacing remain readable with longer Korean text.
- Comparison appears only when existing comparison data is meaningful.
- Comparison is omitted when the model reports insufficient data.
- Sensor data, charts, and splits remain hidden for empty/sparse workouts.
- Feed cards remain visually unchanged.
- Share composer and share card rendering still open from Activity Detail.
- No social, competitive, leaderboard, segment, or ranking behavior is introduced.
- Dynamic Type and VoiceOver labels remain usable for the top summary and rhythm insight.

## Recommendation

Recommendation: ready for device QA.

Rationale:

- Build passed.
- QA found no app-code compile failure.
- QA found no evidence of Mapbox style or Record/Feed/Share code changes.
- Targeted tests remain blocked by CoreSimulator clone infrastructure, not by app/test assertions.

TestFlight decision:

- Do not upload solely from simulator QA.
- Proceed to physical-device QA or a healthy simulator run first.
- If device QA passes the checklist above, Build 8 is a reasonable TestFlight candidate.

## Verification

Commands run:

- `git status --short`
- `git rev-parse --short HEAD`
- `git show --stat --oneline 29d0ded`
- `xcrun simctl list devices available`
- `xcodebuild test -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -only-testing:SOOMTests/ShareableWorkoutCardRendererTests`
- `xcodebuild build -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`

App code changed during QA:

- No.

Final QA classification:

- Blocked by simulator test infrastructure only.
- Ready for device QA.
