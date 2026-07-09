# SOOM FIT Import V1 Parser Foundation

Date: 2026-07-09

## Summary

Implemented FIT Import v1 Phase B: a pure Swift FIT parser foundation for route + summary extraction.

This phase is intentionally narrow:

- No third-party dependency.
- No Activity Detail `.fit` importer entry point.
- No FIT route attachment service.
- No full workout import.
- No sampled stream persistence.
- No TestFlight upload or build number bump.

## Files Changed

- `SOOM/Features/Workout/FITRouteParser.swift`
- `SOOMTests/FITRouteParserTests.swift`
- `SOOM.xcodeproj/project.pbxproj`
- `docs/reports/soom-fit-import-v1-parser.md`

## Parser Behavior

Added:

- `FITRouteParser`
- `FITParsedRoute`
- `FITWorkoutSummary`
- `FITRouteParserError`

Parser input:

- `Data`

Parser output:

- route coordinates
- route distance
- optional summary:
  - sport
  - start date
  - duration
  - distance
  - average speed
  - calories
  - elevation gain
  - average/max heart rate
  - average cadence
  - average power

## Supported FIT Subset

Supported in this foundation:

- normal FIT headers with `.FIT` magic
- 12-byte and 14-byte headers
- normal record headers
- definition messages
- data messages
- little- and big-endian field decoding
- `record` global message `20`
- `session` global message `18`

Supported record fields:

- `timestamp`
- `position_lat`
- `position_long`
- `altitude`
- `heart_rate`
- `cadence`
- `distance`
- `speed`
- `power`

Supported session fields:

- `sport`
- `start_time`
- `total_elapsed_time`
- `total_timer_time`
- `total_distance`
- `total_calories`
- `avg_speed`
- `total_ascent`
- `avg_heart_rate`
- `max_heart_rate`
- `avg_cadence`
- `avg_power`

## Validation Rules

Implemented:

- Empty data fails with `.emptyData`.
- Files over `maximumFileSizeBytes` fail before parsing.
- Invalid or non-FIT headers fail with `.invalidHeader`.
- Declared data size beyond available bytes fails.
- Compressed timestamp headers are rejected with `.unsupportedCompressedTimestampHeader`.
- Data records without prior definitions fail.
- Malformed field data fails cleanly.
- No route coordinates fails with `.noRouteCoordinates`.
- Fewer than two valid coordinates fails.
- Coordinate count over the configured cap fails.

Default limits:

- File size: 10 MB.
- Coordinates: 20,000.

## Tests Added

`FITRouteParserTests` uses synthetic binary FIT fixtures and covers:

- cycling route + session summary extraction
- deriving summary values from record messages when session is absent
- empty data
- non-FIT header
- file size cap
- compressed timestamp header rejection
- data record without definition
- FIT with no route coordinates
- single coordinate failure
- coordinate cap failure

Synthetic fixtures validate the parser structure and SOOM mapping contract. They do not replace real cycling device FIT samples.

## Intentionally Deferred

- real Garmin/Wahoo/Bryton/iGPSPORT/Magene/Coospo fixture validation
- compressed timestamp reconstruction
- developer field interpretation
- broader FIT profile coverage
- lap/event model
- full sampled HR/cadence/power stream persistence
- FIT route attachment service
- full FIT workout import
- Activity Detail `.fit` file importer entry point
- third-party parser dependency review
- server-side parsing

## Real Sample Requirement

Real FIT files are required before SOOM can claim compatibility with cycling computers or external cycling apps.

Required samples remain:

- cycling with GPS route
- cycling without GPS route
- cycling with HR
- cycling with cadence
- cycling with power
- long ride
- short ride
- Garmin/Wahoo/Bryton/iGPSPORT/Magene/Coospo/Chinese cycling computer files if available

## Next Recommended Step

Proceed to Phase C only as a narrow route attachment service built on this parser foundation.

Keep limitations explicit:

- route + summary only
- no full workout import yet
- no UI entry point yet
- no compatibility claims until real FIT samples are validated
