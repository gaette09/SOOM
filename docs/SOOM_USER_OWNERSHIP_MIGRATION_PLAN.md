# SOOM User Ownership Migration Plan

## Purpose

SOOM is local-first today. Supabase account connection can represent who the user is, but it does not automatically move local workouts, settings, routes, course identities, progression summaries, Feed data, Recovery data, or Growth data to remote ownership.

This document defines the v1 ownership migration policy before any schema migration, server write, cloud sync, or account deletion flow exists.

## Ownership Principles

- Local data remains usable without an account.
- Remote account connection is not data migration.
- Migration must require explicit user consent.
- Migration must explain what data types are eligible before anything changes.
- Local workout/settings/route data must not be deleted as part of account linking.
- Account deletion and local data deletion are separate future flows.
- RecoveryCalculator, Growth builders, workout interpretation, HealthKit import, and route persistence do not change for this planning step.

## Current Ownership States

- `localOnly`: the user is using local app data without remote ownership.
- `remoteAccountLinked`: a Supabase session is visible, but local data has not moved.
- `migrationEligible`: local data exists and can be reviewed for future account ownership.
- `migratedFuture`: a future state after explicit consent and a successful migration.
- `conflictFuture`: a future state for resolving overlapping records across devices/accounts.

## Eligible Data Types

Future migration can consider:

- Training settings: maxHR, FTP, preferred units, privacy defaults.
- Workouts: imported/local `UnifiedWorkout` records.
- Workout routes: persisted `WorkoutRoute` records and route privacy metadata.
- Course identities: route-derived course grouping foundations.
- Progression summaries: long-term trend and course progression summaries.
- Future feed posts: only after Feed/SNS ownership exists.

## Migration Triggers

Migration is eligible only after a valid remote account session exists and local data is detected. The app may show a review notice in Settings/My Page, but it must not run migration automatically.

The v1 planner behavior:

- Local-only session -> `notLinked`.
- Remote signed-in plus eligible local data -> `awaitingConsent`.
- Remote signed-in with no eligible local data -> `deferred`.
- Automatic migration -> not allowed.

## Consent UX

Settings/My Page copy should be calm and explicit:

- “이 기기의 기록은 아직 로컬에 있어요.”
- “계정에 연결하려면 다음 단계에서 확인이 필요해요.”
- “동기화와 소유권 이전은 아직 사용하지 않아요.”

Do not use copy that implies backup, cloud sync, or account data transfer before those systems exist.

## Conflict Handling Future

When multiple devices or account histories exist, SOOM should treat conflicts as a review flow. The future conflict state should explain duplicates, overlapping HealthKit imports, route matches, and feed ownership before any merge or delete action.

## Deferred Items

- Supabase database writes.
- SwiftData schema `user_id` migration.
- Cloud sync.
- HealthKit remote sync.
- Account deletion.
- Server-side data deletion.
- Feed/SNS ownership migration.
- Cross-device conflict resolution.
