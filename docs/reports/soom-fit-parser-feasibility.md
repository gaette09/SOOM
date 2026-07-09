# SOOM FIT Parser Feasibility Review

Date: 2026-07-09

## Summary

FIT support does not currently exist in SOOM app code. The current file import path is GPX-only:

- `GPXRouteParser` parses route coordinates from GPX.
- `GPXRouteAttachmentService` attaches parsed GPX routes to existing Apple HealthKit imported workouts.
- Activity Detail exposes the GPX import action only for supported imported workouts with actionable `routeMissingReason`.

Feasibility decision:

- A minimal internal Swift FIT parser scaffold is feasible without a third-party dependency if it is deliberately scoped to route + summary extraction and rejects unsupported FIT variants cleanly.
- Real cycling FIT sample files are still required before claiming broad device compatibility.

## Existing FIT Support

No production FIT parser, FIT attachment service, or FIT file importer exists.

Existing references are planning-only:

- `docs/reports/soom-fit-import-planning.md`
- `docs/reports/soom-file-import-format-roadmap.md`
- `docs/reports/soom-external-route-provider-matrix.md`
- `docs/reports/soom-external-route-source-fallback-plan.md`
- `docs/ops/TODAY_QUEUE.md`

The Activity Detail importer helper currently rejects `.fit` files because it is GPX-only.

## Existing File Import Architecture

The GPX architecture is a good pattern for FIT:

1. Pure parser:
   - accepts `Data`
   - validates file size and structure
   - returns route-ready coordinates and summary metadata
   - throws clear parser errors

2. Attachment service:
   - fetches existing `UnifiedWorkout`
   - refuses unsupported sources
   - refuses silent route replacement
   - persists `WorkoutRoute`
   - clears `routeMissingReason` after successful persistence

3. Activity Detail entry point:
   - shows only from route-missing fallback
   - validates selected file extension
   - reads file locally through security-scoped access
   - routes parse/attach errors to calm Korean copy

## Minimal Internal Parser Scope

The first FIT parser scaffold can safely target:

- normal FIT header with `.FIT` magic
- unsupported compressed timestamp headers rejected
- definition messages
- data messages
- little- and big-endian numeric fields
- route points from record messages
- summary fields from session messages
- clean failure on invalid, empty, oversized, malformed, or unsupported files

Initial message scope:

- `record` global message `20`
- `session` global message `18`

Initial fields:

- `position_lat`
- `position_long`
- `altitude`
- `timestamp`
- `distance`
- `speed`
- `heart_rate`
- `cadence`
- `power`
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
- `sport`

## Limits And Rejections

The scaffold should not pretend to be a complete FIT implementation.

It should reject or ignore safely:

- empty data
- files over a configured size cap
- non-FIT headers
- malformed headers
- data records without definitions
- unsupported compressed timestamp headers
- unsupported base types
- fields that overrun the data section
- fewer than two valid coordinates
- coordinate counts above a configured cap

Deferred until real sample validation:

- developer fields
- compressed timestamp reconstruction
- chained/subfield interpretation
- full FIT profile coverage
- lap/event UI
- sampled stream persistence
- full workout creation

## Dependency Decision

No third-party dependency is required for the next safe implementation phase.

Rationale:

- The immediate goal is a parser foundation that can parse controlled binary fixtures and fail safely.
- A minimal parser is enough to validate SOOM's route + summary mapping contract.
- Dependency review should wait until real sample files show whether the internal scaffold is insufficient.

Stop condition:

- If real Garmin/Wahoo/Bryton/iGPSPORT/Magene/Coospo files require broader FIT profile coverage, pause implementation and review either a vetted Swift package or Garmin reference logic before expanding parser scope.

## Real Sample Requirement

Synthetic fixtures can cover binary structure, field decoding, validation, and SOOM mapping tests.

Real sample FIT files are required before claiming:

- Garmin compatibility
- Wahoo compatibility
- Bryton/iGPSPORT/Magene/Coospo compatibility
- Chinese cycling computer compatibility
- broad FIT route extraction reliability
- sensor stream correctness

## Recommended Next Phase

Proceed to Phase B with a pure Swift `FITRouteParser` foundation:

- no dependencies
- no UI
- no route attachment yet
- route + summary extraction only
- synthetic binary fixture tests
- explicit limitations documented
