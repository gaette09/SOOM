# SOOM 0010 QA Pass 1

Date: 2026-06-23

Source documents:

- `docs/reports/soom-0010-qa-plan.md`
- `docs/reports/soom-0010-qa-execution.md`

Scope: Critical path only.

Requested build: TestFlight build 3.

Execution note: TestFlight build 3 was not installable from this workspace. The local device IPA at `build/SOOM.ipa` reports `CFBundleVersion` `2` and platform `iPhoneOS`. Simulator validation used a local Debug simulator build reporting `CFBundleVersion` `3` on the iPhone 17 simulator.

## QA Session

Tester: Codex

Device:

- D2 simulator: iPhone 17
- UDID: `EA2F4FAE-2E66-42E4-ABA8-73109D60FFD3`
- Runtime: iOS 26.5
- Bundle identifier: `app.soom.prototype`
- Install source: local Xcode Debug simulator build
- Build command: `xcodebuild -project SOOM.xcodeproj -scheme SOOM -configuration Debug -destination id=EA2F4FAE-2E66-42E4-ABA8-73109D60FFD3 -derivedDataPath /tmp/soom-dd build`
- Simulator build number: `3`
- TestFlight physical install: BLOCKED, no accessible TestFlight install/device path in this workspace

Overall result: BLOCKED for release gate, PASS for simulator-covered critical-path evidence.

## Evidence

- Launch screenshot: `/tmp/soom-0010-pass1-launch.png`
- Relaunch screenshot: `/tmp/soom-0010-pass1-relaunch.png`
- Focused test result bundle: `/tmp/soom-dd/Logs/Test/Test-SOOM-2026.06.23_14-20-33-+0900.xcresult`
- Focused tests: PASS, 100 tests, 0 failures
- Initial test attempt: BLOCKED by CoreSimulator clone error; rerun with `-parallel-testing-enabled NO` passed.

Focused passing suites:

- `RecordWorkoutSessionTests`
- `RecordWorkoutSaveFlowTests`
- `WorkoutRoutePersistenceStoreTests`
- `WorkoutRouteStoreTests`
- `WorkoutRouteMapperTests`
- `WorkoutDetailRouteContextProviderTests`
- `WorkoutDetailSectionGroupTests`
- `ShareableWorkoutCardBuilderTests`
- `ShareableWorkoutCardRendererTests`
- `RootAuthBootstrapTests`

## Critical Path Results

| Area | Cases covered | Result | Severity | Notes |
| --- | --- | --- | --- | --- |
| Navigation | NAV-01, NAV-05 partial | PASS on simulator, BLOCKED on TestFlight physical | Blocker | App launched to a valid feed root. After simulator shutdown/reboot and relaunch, it returned to the same valid root state. Direct tab-by-tab tap automation was unavailable in this session. |
| Record | REC-01, REC-02, REC-04, REC-05 partial | PASS by focused tests, BLOCKED for physical GPS | Blocker | Record session logic, start behavior with and without location authorization, route capture seeding, pause/resume/session metrics, and save flow passed focused tests. Real TestFlight GPS capture was not executable. |
| Activity | ACT-01, ACT-02, ACT-03 partial | PASS on simulator evidence and focused tests | Blocker | Feed root rendered with route-backed workout cards and map previews. Activity detail route context and section ordering tests passed. Manual expand/collapse was not executable due tap-control limitation. |
| Share | SHR-01, SHR-02, SHR-03, SHR-04 partial | PASS by focused tests, BLOCKED for native share target completion | High | Share card builder, privacy defaults, route preview attachment, renderer, and activity controller construction tests passed. Native share sheet completion requires manual/physical interaction. |
| Route persistence | RTE-01, RTE-02, RTE-03 partial | PASS by focused tests, BLOCKED for physical route capture | Blocker | Route mapper, route store, persistence upsert/fetch/delete, and workout detail route context tests passed. End-to-end GPS route save/reopen after TestFlight relaunch remains physical-only. |

## Defects

### QA-001: TestFlight build 3 physical install not verified

Severity: Blocker for release gate

Status: BLOCKED

Steps to reproduce:

1. Inspect local distributable metadata with `build/SOOM.ipa`.
2. Compare requested QA target against available install artifacts.
3. Attempt simulator path where possible.

Expected:

- TestFlight build 3 is installable on a physical iPhone, and the QA header can record TestFlight app version, build number, Apple ID/tester group, device model, and iOS version.

Actual:

- No physical TestFlight install path was available in this workspace.
- The local `build/SOOM.ipa` reports build `2`, not build `3`.
- Simulator build `3` was built from source and used for simulator-only validation.

Recommendation:

- Install TestFlight build 3 on a physical iPhone and rerun the D1 critical path: launch/navigation, Record with real GPS, route save, route-backed detail, force quit/relaunch persistence, and native share sheet.
- Confirm whether `build/SOOM.ipa` is stale or unrelated to the requested TestFlight build 3.

### QA-002: Manual simulator tap automation unavailable

Severity: Medium

Status: BLOCKED for manual UI interactions, not an app defect

Steps to reproduce:

1. Launch simulator build 3 with `xcrun simctl launch`.
2. Capture screenshots with `xcrun simctl io ... screenshot`.
3. Attempt to obtain Simulator window bounds for coordinate-based interaction through AppleScript.

Expected:

- The simulator can be tapped programmatically to exercise tab navigation, Record start/stop, detail expand/collapse, and share sheet dismissal.

Actual:

- AppleScript could not resolve the Simulator application object in this session.
- `simctl` supports launch, privacy, location, screenshot, and relaunch, but not direct tap gestures in this environment.

Recommendation:

- Complete the remaining UI gestures manually on a simulator or physical device, or add a dedicated UI test target/harness in a separate task if repeatable automation is required.

## Reproduction Notes

Simulator setup:

1. Built simulator app with Xcode into `/tmp/soom-dd`.
2. Installed app with `xcrun simctl install`.
3. Launched `app.soom.prototype`.
4. Captured launch screenshot.
5. Ran focused critical-path tests with `-parallel-testing-enabled NO`.
6. Booted simulator again after the test runner shut it down.
7. Granted simulator location permission and set fixed simulated location `37.5189,127.1234`.
8. Relaunched app and captured relaunch screenshot.

## Recommendation

Do not expand TestFlight QA based only on this pass. The simulator-covered critical logic is healthy, but the release gate remains blocked until TestFlight build 3 is verified on a physical iPhone with real GPS route capture and native share-sheet interaction.
