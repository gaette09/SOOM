# TCX Persistence Recovery Contract

Status: proposed contract; no production recovery implementation is included in the baseline commit.

## Recommended policy

Policy C — maintain a persistent, idempotent import transaction record. HealthKit route persistence and workout metadata update are separate operations, so a single in-memory transaction cannot guarantee atomicity across the APIs.

## States

`pending` → `attaching-route` → `route-attached` → `metadata-updated` → `completed`

Retryable failures use `failed-retryable`; malformed input, incompatible workout, duplicate route, and unsupported source use `failed-terminal`.

## Required invariants

- Import identity is deterministic from workout ID and source-file digest.
- A route attachment is idempotent; an existing matching route is success, not a duplicate write.
- Metadata update never creates a second route.
- App relaunch resumes only `pending`, `attaching-route`, `route-attached`, and `failed-retryable` records.
- Every transition records attempt count, last error category, and updated time.
- User-visible state distinguishes retryable failure from terminal rejection.
- Recovery must not claim completion until both route and metadata checks pass.

## Policy comparison

| Policy | Strength | Risk | P0 assessment |
| --- | --- | --- | --- |
| A: compensating cleanup | Simple happy path | Cleanup can fail or delete a valid route | Not recommended |
| B: update first | Metadata is visible early | Route failure leaves misleading metadata | Not recommended |
| C: durable idempotent record | Safe restart and retry semantics | Requires a small persistence record | Recommended |

## Approval gates before implementation

1. Confirm transaction-store location and schema.
2. Add crash/relaunch tests for every transition.
3. Verify duplicate route handling against HealthKit on a real device.
4. Verify route-save success followed by metadata-update failure recovery.
5. Decide retention and user-facing retry policy.
