# Backup/Rollback Checklist

## Goal

Create a JAFOM backup and rollback checklist after external production/staging stability has been verified or its gaps are documented.

## Current Status

Next.

This task starts after `tasks/jafom/0001-external-production-staging-stability-check.md` identifies the project root, deployment targets, and current hosting state.

## Acceptance Criteria

- Production and staging targets are known.
- Hosting provider rollback method is documented.
- Database, storage, and environment variable backup responsibilities are identified.
- Rollback authority and approval path are defined.
- A release rollback checklist exists and can be executed without guessing project details.

## Verification Method

- Review hosting dashboard or deployment metadata without deploying.
- Confirm latest known good deployment or commit SHA.
- Confirm backup locations and restore constraints.
- Record rollback steps, required access, expected duration, and validation checks.

## Blockers

- Production/staging target details must be known first.
- Hosting provider, database ownership, and backup mechanism may still be unknown.

## Priority

5. Next JAFOM priority after external stability verification.
