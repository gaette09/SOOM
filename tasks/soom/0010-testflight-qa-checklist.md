# TestFlight QA Checklist

## Goal

Create and run the SOOM TestFlight QA checklist after Record Detail Content Lock has a documented implementation state and verification method.

## Current Status

Next.

This task starts after `tasks/soom/0009-record-detail-content-lock.md` is verified or its remaining gaps are documented.

## Acceptance Criteria

- TestFlight QA scope is documented.
- Required devices, OS versions, accounts, and app build number are identified.
- Core flows for launch, auth, Record Detail, navigation, and release-critical behavior are listed.
- Pass/fail criteria are clear for each QA item.
- Any failed item is converted into a follow-up task or release blocker.

## Verification Method

- Confirm the target TestFlight build number and install path.
- Run the checklist on the agreed device or simulator set.
- Record pass/fail results, screenshots if useful, device/OS details, and unresolved issues.
- Confirm whether the build is ready for internal testing, needs fixes, or is blocked.

## Blockers

- Record Detail Content Lock must be complete enough for QA.
- TestFlight build availability may be blocked by archive signing or upload issues.

## Priority

4. Next SOOM priority after Record Detail Content Lock.
