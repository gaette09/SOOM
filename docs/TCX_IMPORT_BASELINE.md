# TCX Import Baseline

## Scope

This baseline preserves the current TCX route-import change set as one coherent,
reviewable change. It is not a declaration of production readiness or P0
completion.

## Current architecture

- `TCXRouteParser` performs bounded XML parsing and maps supported track data.
- `TCXRouteAttachmentService` attaches route data to compatible HealthKit
  workouts without treating unsupported sources as TCX input.
- Existing workout-library and import surfaces provide the integration boundary.
- Synthetic parser and attachment tests document the currently covered paths.

## Parser and compatibility boundary

The parser handles supported sport/start/duration/distance data and optional
heart-rate, cadence, and elevation samples where present. Malformed XML,
unsupported sources, incompatible workouts, and duplicate attachment attempts
are guarded as failure or no-op outcomes according to the existing service
contract. Time and date behavior still requires fixture-based verification.

## HealthKit attachment flow

The route is persisted through the route attachment service and associated with
the compatible workout. The current implementation should be treated as a
baseline: route-save success followed by workout-update failure may leave a
non-atomic intermediate state that requires explicit recovery design.

## Current verification status

- Synthetic parser and attachment coverage: present.
- Real TCX fixtures: not yet verified.
- Malformed production-like fixtures: not yet verified.
- HealthKit route attachment on a physical device: not yet verified.
- Simulator/build verification: previously blocked before compilation by
  unavailable CoreSimulator/runtime and package-network/cache constraints.
- This commit does not claim a successful compile, device run, or P0 readiness.

## Pre-merge gates

Before merging this baseline to `main`, complete the following gates:

1. Real TCX fixture test.
2. Malformed production-like fixture.
3. Timezone/date fixture.
4. Cadence, heart-rate, and elevation fixture.
5. Duplicate import fixture.
6. HealthKit physical-device route attachment.
7. Route-save success plus workout-update failure recovery.
8. Existing workout plus duplicate route attachment recovery.
9. Offline package dependency/cache resolution.
10. Simulator or physical-device build.

## P0 completion condition

TCX is not marked P0-complete by this baseline commit. P0 requires the gates
above, evidence-backed persistence recovery behavior, and a successful
device-oriented verification run.
