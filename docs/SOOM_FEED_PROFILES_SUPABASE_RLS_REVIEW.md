# SOOM Feed + Profiles Supabase RLS Review

This note documents the finalization pass over `supabase/feed_schema.sql` and the new `supabase/profiles_v1.sql`, following the same review convention as `SOOM_CLUB_SUPABASE_RLS_REVIEW.md`.

Unlike the Club review, this pass was validated by actually running both files against a local PostgreSQL 16 instance (Homebrew, not Docker/Supabase CLI — neither was available in this environment) with a minimal `auth` schema shim (`auth.users`, `auth.uid()`). No production or staging Supabase project was touched — this environment has no Supabase URL/key configured anywhere (checked `Config/LocalSecrets.xcconfig`, `Info.plist`, process env). Applying to the real staging project is still a separate step for whoever holds that project's credentials.

## What Changed in feed_schema.sql

The file previously had zero indexes. `club_foundation_v1.sql` indexes every foreign-key column it has (`clubs.owner_user_id`, `club_members.club_id`, `club_members.user_id`, etc.) — `feed_schema.sql` did not follow that convention. Added, matching the existing house pattern exactly:

- `feed_posts_user_id_idx`
- `feed_posts_created_at_idx` (descending — the eventual feed fetch query sorts by `created_at desc`)
- `feed_post_media_post_id_idx`
- `feed_reactions_post_id_idx`
- `feed_comments_post_id_idx`

These matter for two things: every `_select_visible_parent` policy on the child tables (`feed_post_media`, `feed_reactions`, `feed_comments`) runs an `EXISTS` subquery against `feed_posts` by `post_id` — Postgres does this on every row check under RLS, not just once per query, so an unindexed `post_id` gets expensive as post volume grows. The `created_at` index serves the ordinary feed fetch itself, not RLS.

No RLS recursion bug was found in `feed_schema.sql` (unlike Club's original `club_members_select_scoped`, which queried `club_members` from inside a `club_members` policy). Feed's policies only ever check a *different* table (`feed_posts`) from a child table's policy, or check a plain column on the same row (`feed_posts_select_owner_or_public` reads `user_id`/`visibility` on the row being selected, no subquery) — that shape does not recurse.

The header comment dropped "Draft" and now states its dependency on `profiles_v1.sql` (apply that file first) and its known deferrals (follows graph, photo storage, pagination cursor), matching Club's "Migration foundation only" phrasing.

## profiles_v1.sql — Why It Diverges From Club's Pattern

Club's `SECURITY DEFINER` helper functions (`is_club_member`, `is_club_owner`, `is_club_admin`) exist to avoid RLS self-reference recursion on **read**. Profiles has no such recursion risk — its own review above confirms that. Its `SECURITY DEFINER` function (`handle_new_user`) exists for a different reason: the row has to be created by an `AFTER INSERT ON auth.users` trigger, at a moment when the new user has no authenticated session yet to insert under their own RLS grant. Club never needed this shape, because every `club_members` row is created by an already-authenticated user taking an explicit in-app action (create/join) — an ordinary `to authenticated` insert policy was enough there.

`display_name` defaults, in priority order: Apple Sign In's `full_name` (when present in `auth.users.raw_user_meta_data`) → the local part of the user's email → the literal fallback `"SOOM 사용자"`. `handle` is left `null` at signup — there is no in-app UI yet to set one (deferred, per the roadmap batch scope), so nothing generates one. This was a deliberate default, not a blocking question, on the reasoning that it's a small, cheap-to-change-later choice; flagged for review rather than gated on it.

`public.set_updated_at()` is redefined in `profiles_v1.sql` with `create or replace` even though `club_foundation_v1.sql` already defines the identical function — so `profiles_v1.sql` does not assume Club's migration has already been applied to the same project. Re-applying either file in either order is safe.

## RLS Model (profiles)

- `select`: any authenticated user, no owner scoping — display name/handle are meant to be visible to whoever sees a post or a follow list, and nothing else on the row is sensitive.
- `insert`: no policy. Only `handle_new_user()` (`SECURITY DEFINER`, bypasses RLS) can create a row. A client cannot create a profile for an arbitrary id, including its own — signup is the only entry point.
- `update`: owner only (`id = auth.uid()`).
- `delete`: no policy. Rows are removed only via `auth.users` `ON DELETE CASCADE`.

## Verified by Actual Execution (local Postgres, 2026-08-19)

All of the following were run against a live database, not inferred by reading the SQL:

1. `club_foundation_v1.sql`, `feed_schema.sql`, `profiles_v1.sql` all apply cleanly in either order (profiles-then-feed and feed-then-profiles both tested) against a fresh database with the `auth` schema shim — zero errors.
2. Signup trigger, three cases: Apple `full_name` present → used verbatim; `full_name` absent but email present → email local-part used; neither present → falls back to `"SOOM 사용자"`. All three produced the expected `profiles` row automatically, with no application code involved.
3. Own-row `UPDATE`: succeeds.
4. Cross-user `UPDATE` (authenticated as user A, targeting user B's row): `UPDATE 0` — silently filtered by RLS, not an error, matching Postgres's normal RLS behavior for a non-matching `USING` clause.
5. Direct client `INSERT` (bypassing the trigger, with table-level `INSERT` grant present so the test isn't just catching a missing `GRANT`): rejected with `new row violates row-level security policy` — RLS itself is the blocker, not a permissions accident.
6. Direct client `DELETE`: `DELETE 0` — no matching policy, silently filtered.
7. Any authenticated user reading another user's profile: succeeds, as designed.

## Rollback Order

`profiles_v1.sql`:

1. `drop trigger on_auth_user_created on auth.users;`
2. `drop trigger profiles_set_updated_at on public.profiles;`
3. `drop function public.handle_new_user();`
4. `drop policy "profiles_select_authenticated" on public.profiles;`
5. `drop policy "profiles_update_owner" on public.profiles;`
6. `drop table public.profiles;`

Do not drop `public.set_updated_at()` as part of this rollback if Club's migration is also applied to the same project — it is shared.

## Still Not Done

- Applying either file to the real staging or production Supabase project. This review only ran them locally.
- `handle` uniqueness/format policy and any in-app UI to set it — out of this batch's scope.
- `follows_v1.sql` does not exist yet (next roadmap batch, `feed-follows-table`).
