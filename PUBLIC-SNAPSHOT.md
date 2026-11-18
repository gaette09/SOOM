# Public source snapshot: build 71

This is a sanitized source snapshot, not a byte-for-byte reproduction of the deployed release.

Included roots: SOOM, SOOMTests, SOOMUITests, SOOMWatch, SOOMLiveActivity,
SOOM.xcodeproj, Config, Shared, ThirdParty.

Excluded: local credentials, private fixture directories, evidence, simulator data,
DerivedData, archives, deployment output, and per-user Xcode state.

The owner-specific ApprovedWorkoutMapRepair implementation is replaced with a
fail-closed pass-through. Its private-data integration test is explicitly skipped.
The deployed source is unchanged. Generic route algorithms and tests are retained.

Public builds require locally supplied service configuration; never commit it.
Personal mock display names and the support email are replaced with placeholders.
Public snapshot checks cover excluded paths, known private source identifiers and
credential patterns; synthetic test data and public fallback map coordinates are retained.
The private integration fixture test is intentionally not runnable from this repository.
Build validation status is recorded in the snapshot commit message.
