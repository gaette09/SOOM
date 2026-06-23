# SOOM 0010 TestFlight QA Plan

Date: 2026-06-23

Task: `tasks/soom/0010-testflight-qa-checklist.md`

Status: COMPLETE as a QA checklist and verification plan. NOT EXECUTED against TestFlight yet.

## 1. Record

Device requirements:

- Required: physical iPhone with GPS/location permission support.
- Required: iOS 18 or newer for first release pass.
- Recommended: iPhone 17 Pro or current primary development simulator for layout comparison.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| REC-01 | Open Record from the primary navigation. | Record screen opens without crash, blank map, or stuck loading state. | Blocker |
| REC-02 | Grant location permission from first launch and start a run. | Permission sheet resolves cleanly; recording timer starts; map centers on current or fallback location. | Blocker |
| REC-03 | Deny location permission and return to Record. | App does not crash; user sees a recoverable state; recording cannot silently start with misleading GPS data. | High |
| REC-04 | Start, pause, resume, and stop a recording. | Timer, distance, and state labels remain coherent across transitions. | Blocker |
| REC-05 | Save a completed recording with route points. | Workout appears in the expected post-record destination/feed/detail path with duration, distance, sport, and route availability intact. | Blocker |
| REC-06 | Attempt to stop a too-short or empty session. | App prevents invalid save or records a valid zero/short session according to current product behavior without corrupting later screens. | High |
| REC-07 | Background the app during active recording, then return. | Recording state is preserved or the limitation is clearly recoverable; no crash or duplicated session. | High |

## 2. Activity

Device requirements:

- Required: at least one installed build with seeded/mock or saved activity data.
- Recommended: one device with HealthKit permissions enabled and one with HealthKit unavailable or denied.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| ACT-01 | Open the activity/feed/home surface after launch. | Feed/activity content renders without placeholder-only failure when data exists. | Blocker |
| ACT-02 | Open a route-backed workout detail from the feed. | Detail opens into the map-backed sheet scaffold; route remains visible in preview state. | Blocker |
| ACT-03 | Expand workout detail, scroll content, and collapse back to preview. | Expanded scroll does not expose the map; chevron/handle collapse returns to preview, not minimized. | Blocker |
| ACT-04 | Open a non-route workout detail. | Detail renders fallback visuals and metrics without map-related crash or broken empty states. | High |
| ACT-05 | Review sport-specific metrics for running, cycling, and walking if available. | Labels, units, and metric cards are coherent for each sport. | Medium |
| ACT-06 | Import or preview HealthKit workouts where available. | Permission, import, duplicate handling, and preview results are readable and recoverable. | High |

## 3. Share

Device requirements:

- Required: physical iPhone or simulator with iOS share sheet support.
- Recommended: at least one route-backed workout and one non-route workout.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| SHR-01 | Open share from a workout detail. | Share action opens without blocking the detail sheet or losing navigation state. | High |
| SHR-02 | Generate a share card for a route-backed workout. | Card includes expected summary data and route visual/fallback; no private route endpoints are exposed in visible text. | High |
| SHR-03 | Generate a share card for a non-route workout. | Fallback share visual renders without crash or blank export. | High |
| SHR-04 | Dismiss the native share sheet. | App returns to the same workout detail state without duplicate modals. | Medium |
| SHR-05 | Complete a share target action where available. | Native share flow completes or cancels cleanly; SOOM remains responsive. | Medium |

## 4. Profile

Device requirements:

- Required: signed-in account path or local auth path matching the TestFlight build configuration.
- Recommended: account with existing workouts, clubs, and no-data profile variant.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| PRF-01 | Open Profile from navigation. | Profile renders user identity and summary surfaces without crash. | Blocker |
| PRF-02 | Review profile with no saved workouts. | Empty state is intentional and does not show impossible totals or broken charts. | High |
| PRF-03 | Review profile after saving/importing workouts. | Aggregated workout totals update or the current refresh limitation is documented. | High |
| PRF-04 | Open settings/training settings from Profile. | Settings screen opens and saves/cancels values without navigation loss. | Medium |
| PRF-05 | Sign out or switch account if exposed in the build. | Local/session state is handled according to product expectation; no other user's data appears. | Blocker |

## 5. Club

Device requirements:

- Required: build configured for the current Club data mode, mock or Supabase-backed.
- Recommended: one account with joined clubs and one account with no joined clubs.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| CLB-01 | Open Club/Profile club entry. | Club directory opens without crash or infinite loading. | High |
| CLB-02 | View joined clubs, created clubs, and recommendations. | Sections appear with stable layout; empty states are readable when lists are empty. | Medium |
| CLB-03 | Open a joined club detail. | Identity, rank, member preview, challenges, and membership action render coherently. | High |
| CLB-04 | Open a recommended club detail. | Join/placeholder action state is clear and does not incorrectly claim membership. | Medium |
| CLB-05 | Exercise Club with network unavailable if Supabase-backed. | Network failure is recoverable and does not block unrelated app navigation. | High |

## 6. Recovery

Device requirements:

- Required: device or simulator with local recovery/check-in storage.
- Recommended: physical device with HealthKit read permission allowed and denied variants.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| RCV-01 | Open Recovery from navigation. | Recovery summary renders without crash; loading and empty states resolve. | Blocker |
| RCV-02 | Complete a morning check-in. | Fatigue/soreness/sleep/stress inputs save and update visible recovery context. | High |
| RCV-03 | Edit an existing check-in. | Updated values replace the original record and appear in history/detail. | High |
| RCV-04 | Delete or remove a check-in where available. | Correct record is removed without affecting unrelated check-ins. | Medium |
| RCV-05 | View recovery history/timeline. | Recent entries are sorted correctly and do not duplicate after relaunch. | Medium |
| RCV-06 | Review recovery with no HealthKit data or denied permission. | App presents fallback/mock/local data state without misleading readiness claims. | High |

## 7. Navigation

Device requirements:

- Required: small and large iPhone viewport coverage.
- Recommended: iPhone SE-class simulator and iPhone Pro Max-class simulator if available.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| NAV-01 | Launch from cold start while signed out or local-auth default. | Correct auth or app root appears with no flash-loop or dead end. | Blocker |
| NAV-02 | Move across Home/Activity, Record, Recovery, Profile, and Club surfaces. | Tab/stack state remains coherent; back buttons and selected tabs are correct. | Blocker |
| NAV-03 | Deep navigate into workout detail, settings, check-in detail, and club detail, then return. | Back/dismiss behavior returns to the previous screen without losing root navigation. | High |
| NAV-04 | Rotate device if supported by target build. | Layout does not overlap or trap controls; if portrait-only, orientation lock is consistent. | Medium |
| NAV-05 | Relaunch after force quit. | App restores to a valid root state and does not require reinstall to recover. | Blocker |
| NAV-06 | Test Dynamic Type one size above default. | Primary controls and critical text remain usable; no clipped pass/fail-critical controls. | Medium |

## 8. Weather

Device requirements:

- Required: physical iPhone for live location context if weather uses current location.
- Recommended: network-on and network-off passes.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| WEA-01 | View weather-dependent content on launch or Record. | Weather module loads or falls back without blocking core navigation/recording. | High |
| WEA-02 | Use app with location permission denied. | Weather does not crash and does not show current-location claims without permission. | High |
| WEA-03 | Use app with network disabled after launch. | Cached/fallback weather state is readable; recording and local screens remain usable. | High |
| WEA-04 | Validate Korean/English date, temperature, and condition labels if visible. | Units and text are readable and consistent with the build's locale behavior. | Medium |

## 9. Route Persistence

Device requirements:

- Required: physical iPhone with location permission allowed.
- Recommended: simulator route injection or outdoor short walk/run for reproducible route capture.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| RTE-01 | Record and save a workout with at least three route points. | Route persists and can be fetched after save. | Blocker |
| RTE-02 | Open the saved workout detail immediately after save. | Route-backed detail shows map preview and sheet content without fallback-only visual. | Blocker |
| RTE-03 | Force quit and relaunch, then reopen the saved workout. | Route remains available; no duplicate or missing workout entry. | Blocker |
| RTE-04 | Verify privacy masking/static preview behavior where visible. | Start/end sensitive area is masked or the current privacy behavior is documented as a release decision. | High |
| RTE-05 | Save a workout without captured route. | App stores workout metrics without invalid route payload; detail uses fallback visual. | High |
| RTE-06 | Delete or overwrite route data only if UI exposes it. | Associated detail/feed states update without orphaned route visuals. | Medium |

## 10. Edge Cases

Device requirements:

- Required: at least one clean install and one upgrade/reinstall-over-existing install.
- Required: network toggling, location permission toggling, and low-data/no-data account variant.
- Recommended: low battery mode and poor connectivity physical-device pass.

| ID | Test case | Pass criteria | Severity |
| --- | --- | --- | --- |
| EDG-01 | Clean install, first launch, and first navigation pass. | No migration crash, missing secret crash, or unrecoverable onboarding/auth state. | Blocker |
| EDG-02 | Upgrade install over an existing local data build. | Existing workouts, routes, check-ins, and profile data remain readable or migration gaps are documented. | Blocker |
| EDG-03 | Toggle airplane mode while browsing and recording. | Network-backed surfaces degrade gracefully; active local recording is not corrupted. | High |
| EDG-04 | Revoke location permission from Settings after granting it. | Record/weather surfaces show recoverable permission state and do not continue as if GPS is available. | High |
| EDG-05 | Revoke HealthKit permission after enabling it. | Recovery/activity import views show recoverable state; local data remains accessible. | High |
| EDG-06 | Use very short, very long, and unusually fast activity data. | Metrics and charts do not overflow, divide by zero, or show impossible labels without explanation. | Medium |
| EDG-07 | Tap rapidly on primary navigation, save, share, and dismiss controls. | No duplicate saves, duplicate modals, or stuck disabled controls. | High |
| EDG-08 | Test low-data account across all tabs. | Empty states are intentional and no section exposes mock/test data as real user data. | High |

## TestFlight Verification Setup

Build/install path to record before execution:

- TestFlight app version: TBD.
- TestFlight build number: TBD.
- Apple account/tester group: TBD.
- Install source: TestFlight internal testing invite or App Store Connect internal tester install.
- Bundle identifier expected from prior verification: `app.soom.prototype`.

Required QA devices:

| Device | OS | Purpose | Required |
| --- | --- | --- | --- |
| Physical primary iPhone | iOS 18 or newer | GPS, HealthKit, TestFlight install, permission, route persistence, share sheet | Yes |
| iPhone 17 Pro simulator or current dev simulator | iOS 26.5 or current local runtime | Regression comparison with SOOM 0009 detail behavior | Yes |
| Small-screen iPhone simulator | iOS 18 or newer if available | Layout, navigation, Dynamic Type pressure | Recommended |
| Secondary physical iPhone | Different supported iOS version | Upgrade/reinstall and account/no-data variant | Recommended |

Required accounts and data:

- One TestFlight internal tester Apple ID.
- One SOOM account or local-auth path with existing workouts.
- One clean/no-data account or fresh install state.
- At least one route-backed workout.
- At least one non-route workout.
- At least one Recovery check-in.
- Club state with joined clubs if the build supports account-backed club data.

Evidence to capture:

- Device model and iOS version.
- TestFlight version/build number.
- Pass/fail per case.
- Screenshot or screen recording for every blocker/high failure.
- Console/device logs only for crashes, hangs, or data-loss behavior.
- Follow-up task or release-blocker entry for each failed blocker/high case.

## Release Gate

PASS requires:

- All Blocker cases pass.
- No High case fails without an accepted follow-up decision.
- Route-backed Record Detail behavior remains at least as stable as SOOM 0009 verification.
- TestFlight install path and build number are recorded.
- Any signing/upload gap is converted into SOOM 0011 or a release blocker.

BLOCKED if:

- No TestFlight build can be installed.
- App Store Connect/TestFlight access is unavailable.
- Archive/signing/upload remains unresolved.
- Physical-device GPS route capture cannot be tested.

## Recommended First QA Pass

Run this order first on one physical iPhone from a clean TestFlight install:

1. Record `TestFlight version`, `build number`, device model, and iOS version.
2. Cold launch and complete auth/local session path.
3. Navigate every root surface once: Activity/Home, Record, Recovery, Profile, Club.
4. Run `REC-01` through `REC-05` with a short GPS route.
5. Open the saved route-backed workout and run `ACT-02`, `ACT-03`, `RTE-02`, and `RTE-03`.
6. Run one share-card pass with the saved workout.
7. Complete one Recovery check-in and verify Profile aggregation/empty-state behavior.
8. Toggle airplane mode and verify Weather, Activity, Club, and Recovery degradation.
9. Force quit, relaunch, and reopen the saved workout.
10. Mark release status as ready, needs fixes, or blocked.

Recommended first-pass exit criteria:

- If any Blocker fails, stop broad QA and file the blocker with screenshots/logs.
- If only Medium failures are found, complete the full first pass before triage.
- If signing/TestFlight install is unavailable, stop and move directly to `tasks/soom/0011-fastlane-archive-signing-issue-investigation.md`.

## Completion Status

Result: COMPLETE for SOOM 0010 documentation.

Not executed:

- TestFlight installation.
- Physical-device route capture.
- App Store Connect/internal tester validation.
- Full pass/fail recording against a specific build.

Next required action: execute the recommended first QA pass once a TestFlight build is installable, then update this report or create a dated execution report with actual results.
