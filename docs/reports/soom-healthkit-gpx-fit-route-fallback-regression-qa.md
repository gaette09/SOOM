# SOOM HealthKit / GPX / FIT Route Fallback Regression QA Preview

Date: 2026-07-18

## Scope

Preview-only regression QA plan for route fallback behavior after HealthKit route display, GPX fallback, and FIT Import v1 work. Refreshed on 2026-07-18 as the documentation checklist for a future controlled regression pass.

This is documentation and checklist work only. It does not execute SOOM QA, use real sample files, access production data, call external APIs, bump build numbers, or upload TestFlight.

## Execution Boundary

This checklist distinguishes planning from a later approved test run:

- Use only purpose-built synthetic fixtures and simulator/in-memory test data for any future automated coverage.
- Do not substitute exported HealthKit data, user GPX/FIT files, or files containing real route coordinates.
- Leave every `Result` cell blank until a separately authorized run records the exact command or manual test evidence.
- Treat a simulator infrastructure failure as `Blocked`, not `Pass` or a product regression; retain the failure detail in `Notes`.
- Physical-device validation, real HealthKit data, file-picker interaction, TestFlight, and release actions remain separate approval gates.

## Current Execution Record

The latest synthetic regression attempt (2026-07-16) did not change product code. Focused simulator suites were blocked by the known CoreSimulator clone infrastructure error; generic iOS Simulator `build-for-testing` and repository diff checks passed. This checklist therefore remains a planning artifact and does not claim scenario-level pass results.

## Source Task

- Handoff: `/Volumes/Platinum1TB/SOOM-OS/RUNNER/handoffs/20260709-132021-soom-healthkit-gpx-fit-route-fallback-regression-qa.md`
- Task file: `/Volumes/Platinum1TB/SOOM-OS/TASKS/SOOM/healthkit-route-fallback-regression-qa.md`
- Task status: `ready-preview`

## Files Inspected

- `docs/reports/soom-fit-import-v1-activity-detail-entry.md`
- `docs/reports/soom-gpx-import-v1-activity-detail-entry.md`
- `docs/reports/soom-healthkit-read-phase1c-route-safe-import.md`
- `docs/reports/soom-healthkit-read-phase1d-surface-validation.md`
- `docs/reports/soom-healthkit-cycling-route-diagnosis.md`
- `SOOM/Features/HealthKit/HealthKitWorkoutImportPipeline.swift`
- `SOOM/Features/Workout/ProcessedWorkoutBuilder.swift`
- `SOOM/Features/Workout/GPXRouteAttachmentService.swift`
- `SOOM/Features/Workout/FITRouteAttachmentService.swift`
- `SOOM/Features/Activity/WorkoutDetailContent.swift`
- `SOOM/Features/Activity/ActivityDetailGPXRouteImport.swift`
- `SOOMTests/HealthKitWorkoutImportPipelineTests.swift`
- `SOOMTests/HealthKitImportedWorkoutSurfaceValidationTests.swift`
- `SOOMTests/GPXRouteAttachmentServiceTests.swift`
- `SOOMTests/FITRouteAttachmentServiceTests.swift`
- `SOOMTests/ActivityDetailGPXRouteImportTests.swift`
- `SOOMTests/ProcessedWorkoutBuilderTests.swift`
- `SOOMTests/ShareableWorkoutCardBuilderTests.swift`
- `SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests.swift`

## Current Coverage Baseline

The codebase already has synthetic/local test coverage for the main route fallback paths:

- HealthKit import pipeline route status and `routeMissingReason`.
- HealthKit imported workout surface validation through ProcessedWorkout, Activity/Share/Profile/Recovery-facing paths.
- GPX route parsing and route attachment service behavior.
- FIT route parsing and route attachment service behavior.
- Activity Detail file-import eligibility and error copy for GPX/FIT.
- ProcessedWorkout route fallback behavior when a route is present or missing.

The remaining work is regression QA orchestration, not new product behavior.

## Regression Checklist

Use these checks for a future QA execution pass.

### Result Legend

| Value | Meaning |
| --- | --- |
| Pass | Expected result was observed using approved synthetic test data. |
| Fail | Product behavior differed from the expected result; record a reproducible synthetic case. |
| Blocked | The check could not run because of infrastructure or an approval boundary. |
| N/A | The check does not apply to the selected synthetic scenario; explain why. |

### 1. HealthKit Workout With `HKWorkoutRoute`

| Check | Expected Result | Result | Notes |
| --- | --- | --- | --- |
| Import a HealthKit workout with a shared route. | Workout imports without duplicate replacement. |  |  |
| Persisted route is associated with imported workout id. | Route lookup returns the imported route. |  |  |
| Activity Detail opens the imported workout. | Map route appears and no no-route fallback is shown. |  |  |
| Share opens for the same workout. | Share route uses processed route data. |  |  |
| Profile aggregation includes the workout. | Distance/duration totals remain coherent. |  |  |
| Recovery mapping consumes the workout. | Recovery input mapping remains stable; scoring logic is unchanged. |  |  |

### 2. HealthKit Workout Without Shared Route

| Check | Expected Result | Result | Notes |
| --- | --- | --- | --- |
| Import a HealthKit workout without accessible route samples. | Summary imports; no route is persisted. |  |  |
| `routeMissingReason` is stored. | Reason is not silently dropped. |  |  |
| Activity Detail opens the workout. | No-route fallback copy appears; no broken/blank map state. |  |  |
| GPX/FIT entry eligibility is evaluated. | Route-file import appears only for actionable imported-workout reasons. |  |  |
| Share/Profile/Recovery read the workout. | Surfaces remain coherent with missing route data. |  |  |

### 3. GPX Route Attachment

| Check | Expected Result | Result | Notes |
| --- | --- | --- | --- |
| Attach GPX to supported imported workout missing route. | Route persists and `routeMissingReason` clears to `.none`. |  |  |
| Reopen Activity Detail. | Attached route appears on the map. |  |  |
| Attempt attach when a route already exists. | Existing-route error is shown; no duplicate route is created. |  |  |
| Attempt attach to unsupported/local workout. | Unsupported-source behavior is shown; workout is not modified. |  |  |
| Failed parse or failed persistence path. | Existing workout summary remains intact. |  |  |

### 4. FIT Route Attachment

| Check | Expected Result | Result | Notes |
| --- | --- | --- | --- |
| Attach FIT to supported imported workout missing route. | Route persists and `routeMissingReason` clears to `.none`. |  |  |
| Reopen Activity Detail. | Attached route appears on the map. |  |  |
| Verify cycling route fallback. | Cycling workout remains valid with attached FIT route. |  |  |
| Attempt attach when a route already exists. | Existing-route error is shown; no duplicate route is created. |  |  |
| Failed parse or failed persistence path. | Existing workout summary remains intact. |  |  |

## Future Test Command Proposal

These commands are proposed for a future synthetic regression pass. They were not executed as part of this preview task.

```sh
xcodebuild test -quiet \
  -project SOOM.xcodeproj \
  -scheme SOOM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SOOMTests/HealthKitWorkoutImportPipelineTests \
  -only-testing:SOOMTests/HealthKitImportedWorkoutSurfaceValidationTests \
  -only-testing:SOOMTests/ProcessedWorkoutBuilderTests \
  -only-testing:SOOMTests/ShareableWorkoutCardBuilderTests \
  -only-testing:SOOMTests/UnifiedWorkoutToRecoveryActivityMapperTests
```

```sh
xcodebuild test -quiet \
  -project SOOM.xcodeproj \
  -scheme SOOM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SOOMTests/ActivityDetailGPXRouteImportTests \
  -only-testing:SOOMTests/GPXRouteAttachmentServiceTests \
  -only-testing:SOOMTests/FITRouteAttachmentServiceTests \
  -only-testing:SOOMTests/GPXRouteParserTests \
  -only-testing:SOOMTests/FITRouteParserTests
```

If CoreSimulator clone failures recur, use `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'` as the compile/test-build gate and document simulator execution as infrastructure-blocked.

## Evidence to Record in a Later Approved Run

For each executed checklist section, record only non-sensitive evidence:

| Evidence | Record | Do Not Record |
| --- | --- | --- |
| Test identity | Test target, synthetic fixture label, simulator destination, and result. | HealthKit identifiers, user names, device identifiers, or route coordinates. |
| Failure detail | Assertion/error category and affected checklist row. | Raw GPX/FIT contents, screenshots with personal data, or file paths outside controlled synthetic fixtures. |
| Regression state | Whether route exists, is missing with a reason, or was attached. | Production database values or imported user workout summaries. |
| Infrastructure | Build/test command category and concise block reason. | Environment secrets, signing data, or complete build logs containing sensitive paths. |

## Manual QA Gate For Later

Do not run this as part of the preview task. For later physical-device QA, use synthetic/non-production files first, then approved real sample files only after explicit approval.

| Scenario | Required Later? | Notes |
| --- | --- | --- |
| HealthKit workout with actual shared route. | Yes | Requires device and HealthKit data approval. |
| HealthKit workout without shared route. | Yes | Requires device and HealthKit data approval. |
| GPX attachment through iOS file importer. | Yes | Requires approved sample file. |
| FIT attachment through iOS file importer. | Yes | Requires approved sample file. |
| Activity Detail -> Share -> Profile -> Recovery navigation. | Yes | Device QA only after approval. |

## Stop Conditions Preserved

This preview stopped before:

- TestFlight upload.
- Build number bump.
- Physical-device QA.
- Real sample files.
- Production data access.
- External API calls.
- Secrets or `.env` access.
- Destructive commands.

## Recommendation

The future regression QA task is ready to schedule as a controlled QA pass. The safest next step is to run the synthetic test command set first, then separately request approval for physical-device QA and any real GPX/FIT/HealthKit sample data.

## Verification

- `ops-run-one TASKS/SOOM/healthkit-route-fallback-regression-qa.md`: passed as preview only. The runner did not execute project commands, did not modify SOOM, did not deploy, did not call external APIs, and did not use secrets.
- `git diff --check`: passed.
- `git status --short`: only this new SOOM preview report before commit.
