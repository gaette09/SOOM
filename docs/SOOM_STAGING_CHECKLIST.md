# SOOM Staging Checklist

Purpose: prepare SOOM for internal TestFlight and staging-only Club Supabase validation. Do not apply this checklist directly to production.

## Ground Rules

- Do not run the Club migration against production.
- Do not change production data during this pass.
- Use a disposable or staging Supabase project first.
- Keep local-first fallback enabled in the app.
- Keep real secrets out of git.

## Preflight

- Confirm the working tree is clean before staging DB work.
- Confirm `supabase/club_foundation_v1.sql` is the migration draft under review.
- Confirm `docs/SOOM_CLUB_SUPABASE_RLS_REVIEW.md` has been reviewed.
- Confirm staging Supabase URL and anon key are injected through ignored local config or CI secrets.
- Confirm the app launches with staging auth config and still falls back gracefully when staging is unavailable.

## Club Migration Apply Order

1. Snapshot staging database or create a fresh staging project.
2. Review `supabase/club_foundation_v1.sql` one final time.
3. Apply the migration in staging only.
4. Confirm tables exist:
   - `public.clubs`
   - `public.club_members`
   - `public.club_challenges`
   - `public.club_badges`
5. Confirm helper functions exist:
   - `public.is_club_member(uuid)`
   - `public.is_club_owner(uuid)`
   - `public.is_club_admin(uuid)`
6. Confirm `clubs_set_updated_at` trigger exists.
7. Confirm RLS is enabled on all four tables.

## Rollback Order

Use this order if staging validation fails:

1. Drop badge policies.
2. Drop challenge policies.
3. Drop member policies.
4. Drop club policies.
5. Drop `clubs_set_updated_at` trigger.
6. Drop `public.set_updated_at()`.
7. Drop helper functions:
   - `public.is_club_admin(uuid)`
   - `public.is_club_owner(uuid)`
   - `public.is_club_member(uuid)`
8. Drop child tables:
   - `public.club_badges`
   - `public.club_challenges`
   - `public.club_members`
9. Drop parent table:
   - `public.clubs`

## RLS Helper Checks

- Helpers are `SECURITY DEFINER`.
- Helpers are `stable`.
- Helpers use `set search_path = public`.
- Helpers use `auth.uid()`.
- Helpers are owned by a trusted migration owner.
- No policy on `club_members` directly queries `public.club_members`.

## Owner/Admin/Member Scenarios

- Owner can create an open club.
- Owner can update a club.
- Owner can delete a club.
- Owner can create/update/delete challenges.
- Owner can create/update/delete club badges.
- Admin cannot update club core fields in v1.
- Member can read joined club detail.
- Member can leave a club if not owner.
- Non-member cannot read private club detail.

## Open/Private Club Scenarios

- Open club metadata is readable by authenticated users.
- Open club member list is not globally exposed.
- Open club can be joined by authenticated users.
- Private club metadata is limited to members/owner/admin.
- Private club join is restricted in v1.

## Staging Exit Criteria

- All smoke tests in `docs/SOOM_CLUB_SMOKE_TEST.md` pass.
- App still works when Club service falls back to local-first data.
- No secrets appear in git diff, logs, or crash reports.
- No production database was touched.
