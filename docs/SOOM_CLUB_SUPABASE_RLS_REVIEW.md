# SOOM Club Supabase RLS Review

This note documents the staging-ready RLS hardening pass for `supabase/club_foundation_v1.sql`.

No production or staging database migration has been executed from this review.

## RLS Blocker Fixed

The original `club_members_select_scoped` policy could query `public.club_members` from inside a policy on `public.club_members`.

That self-reference can recurse under Postgres RLS, so the policy now delegates membership checks to `SECURITY DEFINER` helper functions:

- `public.is_club_member(target_club_id uuid)`
- `public.is_club_owner(target_club_id uuid)`
- `public.is_club_admin(target_club_id uuid)`

These helpers are:

- `stable`
- `security definer`
- bound with `set search_path = public`
- scoped to `auth.uid()`

The migration owner must be trusted, and the functions should not be broadened to accept arbitrary user ids in v1.

## Visibility Policy

Open clubs are visible to authenticated users through the `clubs` select policy.

Member lists are not globally exposed just because a club is open. `club_members_select_scoped` now permits:

- the current user's own membership row
- club members
- club owners/admins

Recommended club discovery should rely on `clubs` metadata such as name, intro, sport focus, visibility, and future stored counts rather than exposing the full member list.

## Owner-only Write Policy

For v1, owner-only writes are preferred over broad admin writes:

- club update: owner only
- club delete: owner only
- challenge insert/update/delete: owner only
- badge insert/update/delete: owner only

Admin management can be reintroduced later with column-specific constraints or RPC functions once the moderation model is clearer.

## Updated At

`clubs.updated_at` is now backed by:

- `public.set_updated_at()`
- `clubs_set_updated_at` before-update trigger

## Rollback Order

Rollback should drop child policies/tables before parent tables:

1. Drop `club_badges` policies.
2. Drop `club_challenges` policies.
3. Drop `club_members` policies.
4. Drop `clubs` policies.
5. Drop `clubs_set_updated_at` trigger.
6. Drop helper functions.
7. Drop tables in this order:
   - `club_badges`
   - `club_challenges`
   - `club_members`
   - `clubs`

Do not drop `pgcrypto`; other migrations may depend on it.

## Staging Smoke Test Required

Before production application:

- Apply to a disposable or staging Supabase project.
- Create an owner user and create a club.
- Join as a second user.
- Verify the second user can read only scoped membership rows.
- Verify a third authenticated non-member can read open club metadata but not the member list.
- Verify private clubs are hidden from non-members.
- Verify owners can update/delete clubs.
- Verify admins cannot update clubs in v1.
- Verify owners can create/update/delete challenges and badges.
- Verify rollback SQL runs in the documented order.

## Remaining Needs Review

- Whether open club member counts should be stored on `clubs` or provided by a view/RPC.
- Whether owner delete should be soft delete instead of cascade delete.
- Whether challenge/badge writes should eventually allow admins through a constrained RPC.
- Whether service-role seeding is needed for global badges.
