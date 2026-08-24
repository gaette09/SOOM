-- SOOM Notifications Trigger v1
-- Migration foundation only. Do not apply automatically from the app.
-- Scope: DB trigger that calls the notify-feed-interaction Edge Function
-- after every feed_reactions/feed_comments insert. Requires pg_net
-- (already available on Supabase-hosted projects).
--
-- The webhook secret is read from Supabase Vault (supabase_vault
-- extension), not a custom GUC — Supabase-managed Postgres does not
-- grant permission to set arbitrary app.settings.* parameters via
-- ALTER DATABASE (confirmed: "permission denied to set parameter").
-- Vault is Supabase's supported mechanism for exactly this: an
-- encrypted secret stored in the database, readable only through
-- vault.decrypted_secrets by a role with the right grants (a
-- SECURITY DEFINER function like this one qualifies).
--
-- This file never contains the secret value itself — only the lookup
-- by name. The actual `select vault.create_secret(...)` call that
-- provisions the value is run separately, outside version control
-- (see SOOM-OS/CLAUDE.md for the one-off command).
--
-- current_setting-style fail-closed behavior is preserved: if no
-- secret named 'notify_feed_interaction_webhook_secret' exists yet,
-- the function returns without calling the Edge Function rather than
-- erroring — so applying this migration before the secret is
-- provisioned doesn't break feed_reactions/feed_comments inserts.
--
-- Known gap: net.http_post failures (network error, function down) are
-- silent — no retry, no logging, no dead-letter queue. See
-- notifications-infrastructure in SOOM-OS/ROADMAP.yaml.

create extension if not exists pg_net;
create extension if not exists supabase_vault;

create or replace function public.notify_feed_interaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
begin
  select decrypted_secret into webhook_secret
  from vault.decrypted_secrets
  where name = 'notify_feed_interaction_webhook_secret';

  if webhook_secret is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://wpxllqelmqoysqmzneop.supabase.co/functions/v1/notify-feed-interaction',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || webhook_secret
    ),
    body := jsonb_build_object('table', TG_TABLE_NAME, 'record', row_to_json(new))
  );
  return new;
end;
$$;

drop trigger if exists feed_reactions_notify on public.feed_reactions;
create trigger feed_reactions_notify
after insert on public.feed_reactions
for each row
execute function public.notify_feed_interaction();

drop trigger if exists feed_comments_notify on public.feed_comments;
create trigger feed_comments_notify
after insert on public.feed_comments
for each row
execute function public.notify_feed_interaction();

-- Rollback order:
-- 1. drop trigger if exists feed_comments_notify on public.feed_comments;
-- 2. drop trigger if exists feed_reactions_notify on public.feed_reactions;
-- 3. drop function if exists public.notify_feed_interaction();
-- 4. select vault.delete_secret(id) from vault.decrypted_secrets where name = 'notify_feed_interaction_webhook_secret';
