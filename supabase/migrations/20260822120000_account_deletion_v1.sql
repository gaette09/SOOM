-- SOOM Account Deletion v1
-- Migration foundation only. Do not apply automatically from the app.
-- Scope: a single self-service RPC the client calls to delete the caller's
-- own auth.users row. Required for App Store Review Guideline 5.1.1(v)
-- (an app that supports account creation must offer in-app account
-- deletion).
--
-- No new tables or columns. Every table that references auth.users(id)
-- across profiles_v1.sql, feed_schema.sql, and club_foundation_v1.sql
-- already declares "on delete cascade" on that foreign key, so deleting
-- the auth.users row is sufficient to remove all of the caller's rows
-- everywhere — this file only needs to grant a safe, narrow way to trigger
-- that delete, since the authenticated/anon roles have no direct privilege
-- to delete from auth.users.

-- SECURITY DEFINER so the function can delete from auth.users (a schema the
-- authenticated role has no direct privilege on), scoped to auth.uid() so a
-- caller can only ever delete their own row. Mirrors profiles_v1.sql's
-- handle_new_user(), the existing precedent for a SECURITY DEFINER function
-- that reaches into auth.users on the caller's behalf.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

-- Postgres grants EXECUTE on new functions to PUBLIC by default. This
-- function is destructive and must only ever run for the caller currently
-- authenticated as the row being deleted (auth.uid() is null for anon), so
-- the default grant is revoked and re-granted narrowly.
revoke execute on function public.delete_own_account() from public;
revoke execute on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;

-- Rollback order:
-- 1. revoke execute on function public.delete_own_account() from authenticated;
-- 2. drop function public.delete_own_account();
