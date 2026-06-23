# SOOM 0010 QA Execution Checklist

Date: 2026-06-23

Source plan: `docs/reports/soom-0010-qa-plan.md`

Task: `tasks/soom/0010-testflight-qa-checklist.md`

Status: READY TO EXECUTE. No TestFlight run has been recorded in this file yet.

## 1. Test Order

Use this order for the first executable TestFlight pass. Stop only for Blocker failures or unavailable TestFlight install.

| Order | Area | Cases | Device | Stop condition |
| --- | --- | --- | --- | --- |
| 0 | Setup | Record build, install source, account, device, iOS version | Physical primary iPhone | Stop if TestFlight build cannot be installed |
| 1 | Launch/Auth/Navigation | NAV-01, NAV-02, EDG-01 | Physical primary iPhone | Stop for launch loop, auth dead end, or root navigation crash |
| 2 | Record | REC-01, REC-02, REC-04, REC-05 | Physical primary iPhone | Stop for inability to start, stop, or save a valid workout |
| 3 | Route Persistence | RTE-01, RTE-02, RTE-03 | Physical primary iPhone | Stop for missing route after save or relaunch |
| 4 | Activity Detail | ACT-01, ACT-02, ACT-03, ACT-04 | Physical primary iPhone, then simulator comparison | Stop for route-backed detail crash or minimized/unstable detail state |
| 5 | Share | SHR-01, SHR-02, SHR-03, SHR-04 | Physical primary iPhone | Continue unless share causes crash or data loss |
| 6 | Recovery | RCV-01, RCV-02, RCV-03, RCV-05, RCV-06 | Physical primary iPhone | Stop for Recovery root crash or corrupt saved check-in |
| 7 | Profile | PRF-01, PRF-02, PRF-03, PRF-04, PRF-05 if exposed | Physical primary iPhone | Stop for cross-account data exposure |
| 8 | Club | CLB-01, CLB-02, CLB-03, CLB-04, CLB-05 | Physical primary iPhone | Continue unless Club blocks global navigation |
| 9 | Weather/Network | WEA-01, WEA-02, WEA-03, WEA-04, EDG-03 | Physical primary iPhone | Stop only if offline/weather state blocks recording or app launch |
| 10 | Permission Edges | REC-03, EDG-04, EDG-05 | Physical primary iPhone | Stop for crash, misleading GPS state, or unrecoverable permission state |
| 11 | Layout/Stress | NAV-03, NAV-04, NAV-05, NAV-06, EDG-06, EDG-07, EDG-08 | Small/large simulator plus physical iPhone | Continue unless blocker/high failure appears |
| 12 | Upgrade/Reinstall | EDG-02 | Secondary physical iPhone or same device after data backup | Stop for local data loss or migration crash |

## 2. Critical Path

These cases decide whether the build can continue through broad QA.

| Priority | Cases | Required result |
| --- | --- | --- |
| P0 | Setup, NAV-01, NAV-02, EDG-01 | Installed TestFlight build launches into a usable root state. |
| P0 | REC-01, REC-02, REC-04, REC-05 | User can open Record, grant location, complete a short workout, and save it. |
| P0 | RTE-01, RTE-02, RTE-03 | Saved route persists immediately and after force quit/relaunch. |
| P0 | ACT-02, ACT-03 | Route-backed workout detail opens, expands, scrolls, and collapses to preview without exposing minimized state. |
| P0 | NAV-05 | Force quit/relaunch returns to a valid app state. |
| P1 | PRF-05 if exposed | Sign-out/account behavior does not expose another user's data. |
| P1 | RCV-01, RCV-02 | Recovery opens and can save one check-in. |
| P1 | EDG-03, EDG-04 | Network and location denial do not corrupt recording or misrepresent GPS availability. |

Critical path pass criteria:

- Every P0 item passes on the physical primary iPhone.
- Any P1 failure has a clear product decision or follow-up task before internal testing expands.
- No data-loss, cross-account, launch, recording, or route-persistence issue remains unresolved.

## 3. Device Matrix

Record actual device identifiers before the run.

| Slot | Device | OS | Install source | Account/data state | Required | Assigned cases | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D1 | TBD physical primary iPhone | TBD | TestFlight internal install | Clean install, tester account, location allowed | Yes | Setup, critical path, Record, Route, Activity, Share, Recovery, Profile, Club, Weather, permissions | Pending |
| D2 | iPhone 17 Pro simulator or current dev simulator | iOS 26.5 or current local runtime | Xcode/dev install | Seeded/mock or saved data | Yes | SOOM 0009 comparison, Activity detail, layout smoke | Pending |
| D3 | Small-screen iPhone simulator | TBD | Xcode/dev install | Clean or seeded data | Recommended | Navigation, Dynamic Type, compact layout, edge states | Pending |
| D4 | Secondary physical iPhone | TBD | TestFlight internal install | Upgrade/reinstall or no-data account | Recommended | Upgrade/reinstall, low-data account, HealthKit/location variants | Pending |

Minimum executable matrix:

- D1 is mandatory for TestFlight, GPS, share sheet, permission, HealthKit, and route persistence.
- D2 is mandatory to compare Record Detail behavior with the SOOM 0009 simulator baseline.
- D3 and D4 may be deferred only if D1/D2 pass and the deferral is recorded as a release risk.

## 4. Pass/Fail Recording Format

Build header:

```text
QA session:
Date:
Tester:
TestFlight app version:
TestFlight build number:
Bundle identifier:
Install source:
Apple ID/tester group:
Overall result: PASS / NEEDS FIXES / BLOCKED
```

Device header:

```text
Device ID:
Device model:
iOS version:
Install type: clean / upgrade / reinstall
Account state: signed in / local auth / signed out / no-data
Permissions: location allowed/denied, HealthKit allowed/denied, network on/off
```

Case result row:

| Case ID | Device | Result | Evidence | Issue/follow-up | Notes |
| --- | --- | --- | --- | --- | --- |
| REC-01 | D1 | PASS / FAIL / BLOCKED / SKIP | Screenshot/log path or none | Task/blocker ID or none | Short observation |

Allowed result values:

- PASS: behavior met pass criteria.
- FAIL: behavior was tested and did not meet criteria.
- BLOCKED: case could not run because setup, access, build, device, or earlier dependency failed.
- SKIP: intentionally not run in this session; must include reason.

Failure recording rules:

- Every Blocker or High FAIL must include screenshot, screen recording, crash log, or a written reproduction path.
- Every Blocker FAIL becomes a release blocker.
- Every High FAIL becomes either a release blocker or a named follow-up task with an accepted deferral decision.
- Medium FAIL items can be batched, but must still include expected vs actual behavior.
- Do not mark PASS based on simulator-only evidence for GPS, HealthKit, TestFlight install, or native share-sheet completion.

Issue template:

```text
Issue:
Severity:
Case ID:
Device/OS:
Build:
Steps to reproduce:
Expected:
Actual:
Evidence:
Release decision: blocker / fix before external testing / follow-up accepted
```

## 5. Release Gate Criteria

Ready for internal TestFlight expansion when:

- TestFlight app version and build number are recorded.
- D1 and D2 required matrix slots are complete.
- All P0 critical path cases pass.
- All Blocker-severity cases either pass or are explicitly not applicable to the current build.
- No unresolved High failure affects launch, auth, recording, route persistence, account isolation, data integrity, or navigation.
- Route-backed Record Detail behavior remains at least as stable as `docs/reports/soom-0009-verification.md`.
- Any TestFlight signing/upload gap is tracked under `tasks/soom/0011-fastlane-archive-signing-issue-investigation.md` or a release blocker.

Needs fixes when:

- TestFlight install works, but one or more Blocker cases fail.
- A High failure has no accepted deferral decision.
- Route persistence or Record Detail behavior regresses from SOOM 0009.
- Recovery, Profile, Club, Share, or Weather failure does not block launch/recording but harms the internal tester experience.

Blocked when:

- No TestFlight build can be installed.
- App Store Connect/TestFlight access is unavailable.
- Archive signing/upload remains unresolved.
- Physical-device GPS route capture cannot be tested.
- Auth/session configuration prevents reaching the app root.

## 6. Recommended First QA Session

Session goal: decide whether the current TestFlight build is ready for broader internal testing or should stop for fixes/signing work.

Timebox: 60 to 90 minutes on D1, plus 20 minutes on D2 for Record Detail comparison.

Execution script:

1. Install the TestFlight build on D1 from a clean state.
2. Fill in the build header and D1 device header.
3. Launch cold and run NAV-01, NAV-02, and EDG-01.
4. Open Record and run REC-01, REC-02, REC-04, and REC-05 with a short outdoor route.
5. Open the saved workout and run RTE-01, RTE-02, ACT-02, and ACT-03.
6. Force quit, relaunch, and run NAV-05 plus RTE-03.
7. Run SHR-01 through SHR-04 from the saved workout.
8. Complete RCV-01 and RCV-02.
9. Open Profile and run PRF-01 and PRF-03.
10. Open Club and run CLB-01 through CLB-03.
11. Toggle airplane mode and run WEA-03 plus EDG-03.
12. Revoke location permission and run REC-03, WEA-02, and EDG-04.
13. Install/run the same build or current dev baseline on D2.
14. Repeat ACT-02 and ACT-03 on D2 against the SOOM 0009 baseline behavior.
15. Set overall result to PASS, NEEDS FIXES, or BLOCKED.

First-session expected output:

- Completed build header.
- Completed D1 and D2 device headers.
- Pass/fail rows for all cases in the execution script.
- Evidence for every failure.
- One final release decision:
  - PASS: continue broader internal QA.
  - NEEDS FIXES: fix listed failures before expansion.
  - BLOCKED: unblock TestFlight/signing/access/GPS testability first.

## Completion Status

Result: COMPLETE as an executable checklist.

Not performed:

- No app code changes.
- No TestFlight install.
- No physical-device QA run.
- No deployment.
- No commit.
