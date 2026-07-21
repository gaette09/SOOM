# TCX Fixture Validation Report

This report records deterministic, local, production-like fixture coverage. Fixtures are not a substitute for HealthKit device QA.

## Fixture matrix

| Fixture | Expected result | Coverage |
| --- | --- | --- |
| cycling-normal | parse, 3 points, distance/HR/cadence/elevation | normal cycling |
| running-normal | parse, running mapping | normal running |
| timezone-offset | parse ISO-8601 offset | timezone/date |
| no-timezone | parse with absent timezone metadata where valid | date fallback |
| cadence-heart-rate-elevation | parse optional metrics | optional metrics |
| missing-optionals | parse route without optional metrics | sparse input |
| malformed-xml | reject as malformedXML | malformed input |
| unsupported-sport | parse as `.other`; compatibility policy decides | unsupported source |
| zero-distance | retain route geometry; no invalid division | zero distance |
| duplicate-activity | reject multipleActivities | duplicate activity |
| coordinate-limit | reject coordinateLimitExceeded | bounded parsing |
| inconsistent-summary | preserve parsed summary; attachment compatibility rejects when outside tolerance | consistency guard |

The existing XCTest fixtures in `SOOMTests/TCXRouteParserTests.swift` cover namespaced cycling, default/prefixed namespaces, malformed documents, unsupported shapes, coordinate filtering, and file/lap/coordinate limits. Additional fixture files are intentionally not added to the Xcode target until fixture ownership and resource packaging are approved.

## Current validation

- Parser tests: source inspection confirms deterministic assertions for coordinates, dates, distance, heart rate, cadence, power, and elevation.
- Attachment tests: existing synthetic coverage exercises source, compatibility, duplicate, malformed, and persistence error paths.
- Build: blocked before compilation because CoreSimulatorService is unavailable and cached Swift Package resolution could not be confirmed offline.
- Real fixture and HealthKit route attachment: not verified.

## Merge readiness

`READY_AFTER_DEVICE_QA` — baseline is coherent and test-covered, but P0 completion must wait for real fixture, device HealthKit, and persistence recovery gates.
