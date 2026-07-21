# SOOM TCX Import Planning

Date: 2026-07-18

## Summary

TCX should be SOOM's third route-file format after GPX and FIT. Its first product role should be a compatibility fallback for users who can export a structured TCX activity but cannot provide a FIT file.

Planning decision:

- Implement TCX v1 as route attachment to an existing Apple HealthKit imported workout.
- Parse locally with Foundation `XMLParser`; do not add a dependency.
- Extract one activity's route and bounded summary metadata before any mutation.
- Reuse the existing `WorkoutRoute` persistence and `routeMissingReason` behavior.
- Do not import a new `UnifiedWorkout` in TCX v1.
- Do not persist sampled heart-rate, cadence, power, or speed streams in TCX v1.
- Do not upload or retain the original TCX file.

This document is planning only. It does not add TCX app code, use real sample files, run physical-device QA, bump a build number, or upload TestFlight.

## Current SOOM Baseline

SOOM already has:

- `GPXRouteParser`
- `FITRouteParser`
- `GPXRouteAttachmentService`
- `FITRouteAttachmentService`
- Activity Detail route-file import for `.gpx` and `.fit`
- local `WorkoutRoute` persistence keyed by the existing `UnifiedWorkout.id`
- route replacement protection
- `routeMissingReason` clearing after successful route persistence
- route-backed `ProcessedWorkout`, Activity Detail, Share, comparison, course, and climb consumers

Important current constraints:

- `ActivityDetailGPXRouteFileImport` and related error names are still GPX-specific even though the flow also supports FIT.
- The picker currently rejects `.tcx`.
- `UnifiedDataSource` has no TCX/file-import source case.
- There is no persisted import-origin metadata such as format, parser version, filename hash, or imported-at timestamp.
- There is no atomic full-workout-plus-route import transaction.
- Existing FIT support attaches routes only; it does not create full workouts.
- Existing FIT compatibility is based on synthetic fixtures and still requires approved real samples and physical-device QA.

These constraints make route attachment a safe TCX v1 boundary and make full workout creation a separate later project.

## Format Contract

The canonical format reference is Garmin Training Center Database v2.

Primary schema:

- `TrainingCenterDatabasev2.xsd`
- Namespace: `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2`

Relevant activity structure:

```text
TrainingCenterDatabase
└── Activities
    └── Activity Sport="Running|Biking|Other"
        ├── Id
        └── Lap StartTime="..."
            ├── TotalTimeSeconds
            ├── DistanceMeters
            ├── Calories
            ├── AverageHeartRateBpm/Value
            ├── MaximumHeartRateBpm/Value
            ├── Cadence
            ├── Track
            │   └── Trackpoint
            │       ├── Time
            │       ├── Position
            │       │   ├── LatitudeDegrees
            │       │   └── LongitudeDegrees
            │       ├── AltitudeMeters
            │       ├── DistanceMeters
            │       ├── HeartRateBpm/Value
            │       ├── Cadence
            │       └── Extensions
            └── Extensions
```

Garmin Activity Extension v2 can add:

- trackpoint `TPX/Speed`
- trackpoint `TPX/RunCadence`
- trackpoint `TPX/Watts`
- lap `LX/AvgSpeed`
- lap `LX/MaxBikeCadence`
- lap `LX/AvgRunCadence`
- lap `LX/MaxRunCadence`
- lap `LX/AvgWatts`
- lap `LX/MaxWatts`

Official references:

- https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd
- https://www8.garmin.com/xmlschemas/ActivityExtensionv2.xsd

## Product Scope

### TCX v1: Route Attachment

Target:

- An Apple HealthKit imported workout already exists in SOOM.
- The workout has an actionable missing-route reason.
- The user explicitly selects a `.tcx` activity file.
- The file represents the same workout and contains at least two valid positioned trackpoints.

Behavior:

1. Read the user-selected file through the existing security-scoped file URL flow.
2. Enforce the file-size cap before parsing.
3. Parse exactly one supported TCX activity into an immutable result.
4. Validate route renderability and conservative workout compatibility.
5. Persist a `WorkoutRoute` with the existing workout id.
6. Clear `routeMissingReason` only after route persistence succeeds.
7. Reload route-derived Activity Detail state.
8. Leave the existing HealthKit workout summary unchanged.

TCX summary data is evidence for validation and future work. It is not allowed to overwrite the existing workout in v1.

### Deferred: Full TCX Workout Import

Full workout creation is deferred until SOOM has:

- a file-import data source/origin model
- a stable external id or privacy-preserving file fingerprint policy
- an atomic workout-plus-route persistence operation
- an explicit duplicate review path for file imports
- source-priority rules for HealthKit versus user-selected files
- deletion semantics for imported file-derived data
- a data-quality policy for partial TCX summaries

Full import must not be added as a side effect of route attachment.

## Parser Strategy

### Decision

Use a small internal Swift parser built on Foundation `XMLParser`.

Why:

- TCX is XML and does not require the binary profile handling needed by FIT.
- SOOM already ships an `XMLParser`-based GPX parser.
- The initial activity/route subset is bounded.
- Local parsing matches the current privacy posture.
- A third-party XML or TCX package would add license, security, and maintenance surface without a demonstrated v1 need.

### Proposed Types

```swift
struct TCXParsedRoute: Equatable {
    let coordinates: [WorkoutRouteCoordinate]
    let totalDistanceMeters: Double
    let summary: TCXWorkoutSummary
}

struct TCXWorkoutSummary: Equatable {
    let workoutType: UnifiedWorkoutType?
    let activityId: String?
    let startDate: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let averageSpeedMetersPerSecond: Double?
    let activeEnergyKcal: Double?
    let elevationGainMeters: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let averageCadence: Double?
    let averagePower: Double?
}
```

The parser should return data only. It must not access stores, mutate a workout, or trigger UI state.

### Supported v1 Document Shape

Accept:

- `TrainingCenterDatabase` root
- one `Activities/Activity`
- one or more `Lap` elements in that activity
- one or more `Track` elements per lap
- positioned `Trackpoint` elements in document order
- prefixed or default Garmin v2 namespaces
- known Activity Extension v2 elements
- unknown extensions ignored without treating their local names as core fields

Reject explicitly:

- no `Activity`
- more than one activity candidate
- `MultiSportSession`
- course-only TCX
- workout-definition-only TCX
- fewer than two valid positioned trackpoints
- an activity that exceeds configured lap, trackpoint, or coordinate limits

SOOM must not concatenate unrelated activities or silently choose the first activity from a multi-activity export.

### Namespace Rules

- Require the root local name `TrainingCenterDatabase`.
- Prefer the Garmin v2 namespace.
- Normalize qualified names so common namespace prefixes do not change parsing.
- Keep extension parsing namespace-aware: `Watts` or `Speed` counts only inside a recognized Activity Extension `TPX`/`LX` context.
- Do not treat an arbitrary vendor element with the same local name as a trusted Garmin field.
- Empty or nonstandard namespaces may be evaluated only with real fixtures; they are not a compatibility claim in v1 planning.

### XML Safety And Limits

Default proposal:

- maximum file size: 10 MB
- maximum coordinates: 20,000
- maximum activities: 1
- maximum laps: 500
- maximum accumulated text for one scalar field: 4 KB
- external entity resolution: disabled

Required behavior:

- reject empty data before constructing `XMLParser`
- keep `shouldResolveExternalEntities` disabled
- abort as soon as a hard limit is exceeded
- fail safely on malformed XML
- never log raw file contents, coordinates, or health metrics
- never mutate app state until parsing and validation both succeed

Proposed parser errors:

- `emptyData`
- `fileTooLarge(maximumBytes:)`
- `malformedXML`
- `unsupportedRoot`
- `noActivity`
- `multipleActivities`
- `unsupportedMultiSport`
- `noRouteCoordinates`
- `insufficientValidCoordinates(validCount:)`
- `coordinateLimitExceeded(maximumCoordinates:)`
- `lapLimitExceeded(maximumLaps:)`
- `invalidActivity`

## Field Mapping Rules

### Route Coordinates

Map each valid positioned trackpoint to:

- `LatitudeDegrees` -> `WorkoutRouteCoordinate.latitude`
- `LongitudeDegrees` -> `WorkoutRouteCoordinate.longitude`
- `AltitudeMeters` -> `WorkoutRouteCoordinate.altitude`
- `Time` -> `WorkoutRouteCoordinate.timestamp`

Rules:

- preserve lap/track/trackpoint document order
- accept latitude from `-90...90`
- accept longitude from `-180...180`
- drop a malformed or out-of-range positioned point
- do not create a coordinate from time/distance without a position
- fail if fewer than two valid coordinates remain
- do not smooth, snap, interpolate, or reorder coordinates

### Sport

- `Biking` -> `.cycling`
- `Running` -> `.running`
- `Other` -> `.other`

TCX v1 should use sport for compatibility validation only. It must not reclassify the existing HealthKit workout.

### Time

Priority:

1. `Activity/Id` when it is a valid timestamp
2. first `Lap@StartTime`
3. first valid trackpoint time

Duration:

1. sum valid nonnegative lap `TotalTimeSeconds`
2. otherwise last valid trackpoint time minus first valid trackpoint time

If `Activity/Id` and the first lap start differ materially, preserve both internally for validation and do not silently repair the file.

### Distance

Summary distance:

1. sum valid nonnegative lap `DistanceMeters`
2. otherwise use the maximum monotonic trackpoint `DistanceMeters` value within laps
3. otherwise unavailable

Route persistence distance:

1. validated TCX summary distance when present and plausible
2. coordinate-derived haversine distance as fallback

The parser should always calculate coordinate-derived distance for validation. A nonpositive, nonfinite, or grossly implausible summary distance must not replace the coordinate-derived fallback.

### Calories

- sum valid lap `Calories`
- zero is treated as unavailable unless fixture evidence shows it is an intentional measured value
- do not derive calories from heart rate, power, duration, or distance

### Heart Rate

Summary priority:

1. duration-weighted lap `AverageHeartRateBpm/Value`
2. arithmetic mean of valid trackpoint `HeartRateBpm/Value`

Maximum:

1. maximum lap `MaximumHeartRateBpm/Value`
2. maximum valid trackpoint heart rate

Values must be finite and physiologically representable by the schema. Missing values stay `nil`.

### Cadence

Cycling:

- lap `Cadence` may provide average bike cadence
- trackpoint `Cadence` may provide bike cadence

Running:

- Activity Extension `LX/AvgRunCadence`
- Activity Extension `TPX/RunCadence`

Summary priority:

1. duration-weighted compatible lap average
2. arithmetic mean of valid compatible trackpoints

Do not combine bike cadence and run cadence in one average.

### Power And Speed Extensions

Power:

1. duration-weighted Activity Extension `LX/AvgWatts`
2. arithmetic mean of valid `TPX/Watts`

Average speed:

1. duration-weighted `LX/AvgSpeed`
2. distance divided by duration when both are valid
3. arithmetic mean of valid `TPX/Speed` only as a last bounded fallback

Power and speed values are summary-only in v1. Their sample streams are not persisted.

### Elevation Gain

- derive positive altitude deltas from valid route coordinates
- do not infer ascent from start/end altitude alone
- do not use an unknown vendor extension without a separate reviewed mapping

## Route Attachment Compatibility

The route attachment service should retain all existing guardrails:

- workout must exist
- source must be `.appleHealthKit`
- an existing route is not replaced by default
- parse failure does not modify the workout
- route persistence failure preserves the workout summary
- `routeMissingReason` clears only after route save succeeds

TCX provides enough summary data to add a conservative compatibility check before persistence.

Required checks when both sides provide the field:

- sport must be compatible
- start time difference should be within 5 minutes
- duration difference should be within 10%
- distance difference should be within 15%

Policy:

- a clear mismatch blocks attachment and reports that the file appears to describe another workout
- missing optional TCX summary fields do not automatically block a user-selected route
- `.other` does not override a more specific HealthKit sport
- no automatic route replacement or destructive merge

The exact thresholds must be fixture-tested. They are intentionally slightly broader than the current full-workout duplicate engine because exports may round lap summaries.

## UI Integration Plan

Before exposing TCX, rename the generic route-file surface:

- `ActivityDetailGPXRouteFileImport` -> `ActivityDetailRouteFileImport`
- `RouteFileFormat` adds `.tcx`
- GPX-specific eligibility naming becomes route-file generic
- `.invalidGPX` display state becomes `.invalidRouteFile`

Picker:

- add `.tcx` UTType from filename extension when available
- retain extension validation after selection
- continue reading through security-scoped access

Copy:

- unsupported: `GPX, FIT 또는 TCX 파일만 가져올 수 있습니다.`
- help: `원본 앱에서 GPX, FIT 또는 TCX 파일을 내보내면 이 운동에 경로를 추가할 수 있습니다.`
- mismatch: `선택한 파일이 이 운동과 일치하지 않습니다.`
- malformed/unreadable: keep the generic `경로 파일을 읽을 수 없습니다.`

Dispatch:

- `.gpx` -> existing GPX service
- `.fit` -> existing FIT service
- `.tcx` -> new TCX service

The screen should keep one route-file action rather than adding a separate TCX button.

## Implementation Phases

### Phase A: Parser Foundation

Add:

- `SOOM/Features/Workout/TCXRouteParser.swift`
- `SOOMTests/TCXRouteParserTests.swift`
- Xcode project membership

Acceptance:

- pure parser, no store/UI dependency
- core Garmin v2 activity fields
- multi-lap/multi-track ordering
- Activity Extension v2 summary fields
- explicit limits and safe failures
- synthetic fixtures only

### Phase B: Route Attachment Service

Add:

- `SOOM/Features/Workout/TCXRouteAttachmentService.swift`
- `SOOMTests/TCXRouteAttachmentServiceTests.swift`

Acceptance:

- attaches only to supported existing workouts
- conservative compatibility validation
- no silent replacement
- route uses existing workout id
- successful save clears `routeMissingReason`
- failure leaves summary intact
- `ProcessedWorkoutBuilder` consumes the route

Keep the service format-specific for v1 unless extracting shared attachment mechanics can be proven behavior-preserving with GPX/FIT regression tests.

### Phase C: Activity Detail Entry

Update:

- generic route-file helper names
- picker content types and extension detection
- dependency wiring in `UnifiedWorkoutLibraryViewContainer`
- route dispatch in `UnifiedWorkoutLibraryView`
- calm Korean copy
- Activity Detail route import tests

Acceptance:

- `.tcx` is accepted case-insensitively
- unsupported extensions remain rejected
- success refreshes persisted route and derived state
- all GPX/FIT behavior remains unchanged

### Phase D: Synthetic Regression

Run focused tests for:

- TCX parser
- TCX attachment
- GPX parser/attachment
- FIT parser/attachment
- Activity Detail route-file import
- `ProcessedWorkoutBuilder`
- route-backed Share/Profile/Recovery-facing mappings

Compile gates:

```sh
xcodebuild build-for-testing -quiet \
  -project SOOM.xcodeproj \
  -scheme SOOM \
  -destination 'generic/platform=iOS Simulator'
```

```sh
xcodebuild build -quiet \
  -project SOOM.xcodeproj \
  -scheme SOOM \
  -destination 'generic/platform=iOS Simulator'
```

### Phase E: Approved Real-File And Device QA

Separate approval is required before:

- using any real TCX activity file
- physical-device file-picker QA
- using health/location/sensor samples
- build number changes
- TestFlight upload

Required real-file matrix after approval:

- cycling TCX with route
- running TCX with route
- multiple laps and tracks
- route with missing altitude
- route with missing HR/cadence/power
- Activity Extension v2 speed/power
- TCX without positions
- multi-activity export
- malformed or truncated TCX
- exports from at least two target apps/platforms

Compatibility claims must be limited to validated exporters.

## Synthetic Test Matrix

Parser success:

- default Garmin v2 namespace
- prefixed Garmin v2 namespace
- two positioned trackpoints
- multiple laps and tracks preserve order
- fractional and nonfractional ISO-8601 timestamps
- optional altitude
- lap summaries
- standard HR/cadence
- Activity Extension v2 speed/power
- unknown extension ignored

Parser failure:

- empty file
- oversized file
- malformed XML
- wrong root
- no activity
- more than one activity
- multisport session
- course-only file
- no positioned points
- one valid positioned point
- out-of-range coordinates
- coordinate limit
- lap limit

Attachment:

- matching route attaches
- sport mismatch blocks
- time mismatch blocks
- duration mismatch blocks
- distance mismatch blocks
- missing optional summary still permits explicit route attachment
- existing route is not replaced
- local SOOM workout is rejected
- persistence failure preserves summary
- successful attachment clears the missing-route reason

Regression:

- `.gpx` and `.fit` remain accepted
- `.xml` remains rejected despite XML picker fallback
- GPX/FIT errors keep generic display behavior
- Activity Detail route-derived state refresh still occurs

## Privacy And Storage

- Parse only a user-selected file.
- Parse locally.
- Do not upload the original TCX.
- Do not retain the original TCX.
- Do not log raw XML, coordinates, filenames, device ids, or sensor values.
- Persist only the route data required by existing workout surfaces.
- Treat route and sensor-derived summaries as sensitive health/location data.
- Do not add cloud sync in TCX v1.

Future import-origin metadata requires a separate storage/privacy review before persistence.

## Risks And Stop Conditions

Stop and review before expanding if:

- real exporters require permissive XML handling that weakens parser safety
- a file contains multiple activities or multisport sessions
- vendor extensions conflict with Garmin namespaces
- summary fields disagree materially with route geometry
- full workout creation is requested before file-origin and duplicate contracts exist
- a third-party dependency becomes necessary
- server upload is proposed

## Completion Criteria For Planning

Planning is complete when:

- v1 is fixed to route attachment only
- parser and namespace rules are explicit
- field mappings and missing-data behavior are explicit
- multi-activity behavior is explicit
- attachment match rules are explicit
- implementation phases and test gates are explicit
- real-file/device/release approval gates are preserved

## Recommended Next Step

Proceed to Phase A only: implement the pure `TCXRouteParser` and synthetic tests.

Stop after the parser foundation for review before adding persistence or UI.
