-- Batch 6 of the notifications infrastructure: batch-style cleanup of
-- permanently invalid APNs device tokens. The Edge Function marks a token
-- invalid (last_invalid_reason/invalidated_at) the moment APNs returns a
-- permanent-failure reason (BadDeviceToken/Unregistered/
-- DeviceTokenNotForTopic) — it does not delete immediately. This cron job
-- sweeps marked rows on a schedule instead, per 2026-08-24 product decision.
-- Transient failures (5xx, rate limiting, other 400 reasons) are never
-- marked, so they're never swept — only tokens APNs has explicitly said
-- will never work again.

alter table public.device_tokens
    add column if not exists last_invalid_reason text,
    add column if not exists invalidated_at timestamptz;

-- pg_cron installs into its own schema; the cleanup function lives in
-- public like the rest of this project's functions and is what the cron
-- job actually calls.
create extension if not exists pg_cron;

create or replace function public.cleanup_invalidated_device_tokens()
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.device_tokens
    where invalidated_at is not null;
$$;

-- Idempotent: unschedule any prior job with this name before
-- (re)registering, so re-running this migration (or a future one that
-- adjusts the schedule) doesn't create duplicate jobs.
select cron.unschedule(jobid)
from cron.job
where jobname = 'cleanup-invalidated-device-tokens';

select cron.schedule(
    'cleanup-invalidated-device-tokens',
    '0 3 * * *', -- daily at 03:00 UTC — low traffic, no urgency to sweep faster
    $$select public.cleanup_invalidated_device_tokens();$$
);
