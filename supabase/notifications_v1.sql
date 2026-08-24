-- SOOM Notifications Foundation v1
-- Migration foundation only. Do not apply automatically from the app.
-- Scope: schema only — device_tokens (APNs token registry) and
-- notifications (per-user notification records), plus the RLS a client
-- needs to register a token and read/mark-read its own notifications.
-- Deferred: the INSERT trigger/Edge Function that actually populates
-- notifications from feed_reactions/feed_comments (next batch, once the
-- APNs auth key is in place) and any client-side insert path — rows are
-- only ever created by that future SECURITY DEFINER trigger function, the
-- same shape as profiles_v1.sql's handle_new_user().
--
-- Depends on profiles_v1.sql (auth.users(id) rows exist) and
-- feed_schema.sql (notifications.post_id references feed_posts).

create table if not exists public.device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null,
    platform text not null default 'ios' check (platform in ('ios')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, token)
);

create table if not exists public.notifications (
    id uuid primary key default gen_random_uuid(),
    recipient_id uuid not null references auth.users(id) on delete cascade,
    actor_id uuid references auth.users(id) on delete cascade,
    type text not null check (type in ('reaction', 'comment')),
    post_id uuid references public.feed_posts(id) on delete cascade,
    body text,
    read_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists device_tokens_user_id_idx on public.device_tokens(user_id);
create index if not exists notifications_recipient_id_idx on public.notifications(recipient_id);
create index if not exists notifications_created_at_idx on public.notifications(created_at desc);

-- Reuses profiles_v1.sql's exact set_updated_at() definition (create or
-- replace, so re-applying any of these foundation files is order-independent).
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

drop trigger if exists device_tokens_set_updated_at on public.device_tokens;
create trigger device_tokens_set_updated_at
before update on public.device_tokens
for each row
execute function public.set_updated_at();

alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;

-- device_tokens: a user only ever manages their own tokens (register on
-- launch, upsert on refresh, delete on sign-out/uninstall detection).
drop policy if exists "device_tokens_select_owner" on public.device_tokens;
create policy "device_tokens_select_owner"
on public.device_tokens for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "device_tokens_insert_owner" on public.device_tokens;
create policy "device_tokens_insert_owner"
on public.device_tokens for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "device_tokens_update_owner" on public.device_tokens;
create policy "device_tokens_update_owner"
on public.device_tokens for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "device_tokens_delete_owner" on public.device_tokens;
create policy "device_tokens_delete_owner"
on public.device_tokens for delete
to authenticated
using (user_id = auth.uid());

-- notifications: recipient can read their own notifications and mark them
-- read. No insert/delete policy for the client — rows are only ever
-- created by the future trigger function (SECURITY DEFINER, bypasses RLS)
-- and are never deleted by the client, mirroring profiles_v1.sql's
-- "no insert policy" convention for handle_new_user()-only rows.
drop policy if exists "notifications_select_recipient" on public.notifications;
create policy "notifications_select_recipient"
on public.notifications for select
to authenticated
using (recipient_id = auth.uid());

drop policy if exists "notifications_update_read_at_recipient" on public.notifications;
create policy "notifications_update_read_at_recipient"
on public.notifications for update
to authenticated
using (recipient_id = auth.uid())
with check (recipient_id = auth.uid());

-- Rollback order:
-- 1. drop policy "notifications_update_read_at_recipient" on public.notifications;
-- 2. drop policy "notifications_select_recipient" on public.notifications;
-- 3. drop policy "device_tokens_delete_owner" on public.device_tokens;
-- 4. drop policy "device_tokens_update_owner" on public.device_tokens;
-- 5. drop policy "device_tokens_insert_owner" on public.device_tokens;
-- 6. drop policy "device_tokens_select_owner" on public.device_tokens;
-- 7. drop trigger device_tokens_set_updated_at on public.device_tokens;
-- 8. drop table public.notifications;
-- 9. drop table public.device_tokens;
-- (public.set_updated_at() is shared with profiles/club — do not drop it
-- here if those migrations are also applied to the same project.)
