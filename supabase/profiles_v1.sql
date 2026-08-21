-- SOOM Profiles Foundation v1
-- Migration foundation only. Do not apply automatically from the app.
-- Scope: minimal public identity (display name, handle) auto-provisioned at signup.
-- Deferred: avatar storage, bio, in-app profile edit UI, handle change flow.
--
-- This table is a prerequisite for feed_schema.sql's author display and for
-- the future follows_v1.sql graph (both need a display name/handle to show
-- for a user_id). It is deliberately its own file rather than folded into
-- feed_schema.sql or club_foundation_v1.sql: identity is a cross-feature
-- concern, not owned by Feed or Club.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null,
    handle text unique,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists profiles_handle_idx on public.profiles (handle);

-- Auto-provisioning trigger.
--
-- Unlike club_foundation_v1.sql's SECURITY DEFINER helpers (which exist to
-- avoid self-referencing RLS recursion on read), this SECURITY DEFINER
-- function exists because the row must be created at signup time, before
-- the new user has an authenticated session to insert under their own RLS
-- grant. Club never needed this shape: every club_members row is created by
-- an already-authenticated user taking an explicit in-app action (create/
-- join), so ordinary "to authenticated" insert policies were sufficient
-- there. Profile provisioning has no such moment — it has to run as the
-- trigger owner, not as the new user.
--
-- display_name default: Apple Sign In's full name (when present in
-- raw_user_meta_data) > email local-part > a literal fallback. handle is
-- left null; there is no in-app UI yet to set it (deferred, see scope
-- note above), so nothing generates one at signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(split_part(new.email, '@', 1), ''),
      'SOOM 사용자'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

-- Reuses club_foundation_v1.sql's exact set_updated_at() definition.
-- Redefined here (create or replace, so re-applying either file is safe
-- regardless of order) so this file does not assume Club's migration has
-- already been applied — the two foundations are independent.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

alter table public.profiles enable row level security;

-- Display names/handles are meant to be visible to anyone viewing a post
-- or a follow list, so read is open to any authenticated user (no owner
-- scoping) — the only public-facing fields here are name/handle, nothing
-- sensitive.
drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles for select
to authenticated
using (true);

-- No insert policy: rows are created only by handle_new_user() above,
-- which runs as SECURITY DEFINER and bypasses RLS. A client-side insert
-- policy is intentionally absent so the client cannot create a profile
-- row for an id that is not its own (or for one that already exists).
drop policy if exists "profiles_update_owner" on public.profiles;
create policy "profiles_update_owner"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- No delete policy: profile rows are removed by the auth.users ON DELETE
-- CASCADE, not by a direct client delete.

-- Rollback order (mirrors club_foundation_v1.sql's convention):
-- 1. drop trigger on_auth_user_created on auth.users;
-- 2. drop trigger profiles_set_updated_at on public.profiles;
-- 3. drop function public.handle_new_user();
-- 4. drop policy "profiles_select_authenticated" on public.profiles;
-- 5. drop policy "profiles_update_owner" on public.profiles;
-- 6. drop table public.profiles;
-- (public.set_updated_at() is shared with Club — do not drop it here if
-- Club's migration is also applied to the same project.)
