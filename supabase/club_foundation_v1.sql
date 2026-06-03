-- SOOM Club Supabase Foundation v1
-- Migration foundation only. Do not apply automatically from the app.
-- Scope: club directory, creation, membership, challenge/badge catalog foundation.
-- Deferred: ranking engine, challenge progress engine, invite graph, moderation tools.

create extension if not exists pgcrypto;

create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  intro text,
  purpose text,
  sport_focus text,
  visibility text not null default 'open'
    check (visibility in ('open', 'private')),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member'
    check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  unique (club_id, user_id)
);

create table if not exists public.club_challenges (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null,
  description text,
  metric_type text not null
    check (metric_type in ('distance', 'workoutCount', 'consistency', 'recovery')),
  target_value double precision not null default 0,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.club_badges (
  id uuid primary key default gen_random_uuid(),
  club_id uuid references public.clubs(id) on delete cascade,
  title text not null,
  description text,
  rarity text not null default 'common'
    check (rarity in ('common', 'uncommon', 'rare')),
  created_at timestamptz not null default now()
);

create index if not exists clubs_owner_user_id_idx on public.clubs(owner_user_id);
create index if not exists club_members_club_id_idx on public.club_members(club_id);
create index if not exists club_members_user_id_idx on public.club_members(user_id);
create index if not exists club_challenges_club_id_idx on public.club_challenges(club_id);
create index if not exists club_badges_club_id_idx on public.club_badges(club_id);

alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_challenges enable row level security;
alter table public.club_badges enable row level security;

drop policy if exists "clubs_select_open_or_member" on public.clubs;
create policy "clubs_select_open_or_member"
on public.clubs for select
to authenticated
using (
  visibility = 'open'
  or owner_user_id = auth.uid()
  or exists (
    select 1 from public.club_members cm
    where cm.club_id = clubs.id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "clubs_insert_owner" on public.clubs;
create policy "clubs_insert_owner"
on public.clubs for insert
to authenticated
with check (owner_user_id = auth.uid());

drop policy if exists "clubs_update_owner_admin" on public.clubs;
create policy "clubs_update_owner_admin"
on public.clubs for update
to authenticated
using (
  owner_user_id = auth.uid()
  or exists (
    select 1 from public.club_members cm
    where cm.club_id = clubs.id
      and cm.user_id = auth.uid()
      and cm.role in ('owner', 'admin')
  )
)
with check (
  owner_user_id = auth.uid()
  or exists (
    select 1 from public.club_members cm
    where cm.club_id = clubs.id
      and cm.user_id = auth.uid()
      and cm.role in ('owner', 'admin')
  )
);

drop policy if exists "club_members_select_scoped" on public.club_members;
create policy "club_members_select_scoped"
on public.club_members for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.clubs c
    where c.id = club_members.club_id
      and c.visibility = 'open'
  )
  or exists (
    select 1 from public.club_members cm
    where cm.club_id = club_members.club_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "club_members_insert_join_open" on public.club_members;
create policy "club_members_insert_join_open"
on public.club_members for insert
to authenticated
with check (
  user_id = auth.uid()
  and (
    role = 'member'
    or exists (
      select 1 from public.clubs c
      where c.id = club_members.club_id
        and c.owner_user_id = auth.uid()
        and role = 'owner'
    )
  )
  and exists (
    select 1 from public.clubs c
    where c.id = club_members.club_id
      and (c.visibility = 'open' or c.owner_user_id = auth.uid())
  )
);

drop policy if exists "club_members_delete_self_non_owner" on public.club_members;
create policy "club_members_delete_self_non_owner"
on public.club_members for delete
to authenticated
using (
  user_id = auth.uid()
  and role <> 'owner'
);

drop policy if exists "club_challenges_select_visible_club" on public.club_challenges;
create policy "club_challenges_select_visible_club"
on public.club_challenges for select
to authenticated
using (
  exists (
    select 1 from public.clubs c
    where c.id = club_challenges.club_id
      and (
        c.visibility = 'open'
        or c.owner_user_id = auth.uid()
        or exists (
          select 1 from public.club_members cm
          where cm.club_id = c.id
            and cm.user_id = auth.uid()
        )
      )
  )
);

drop policy if exists "club_badges_select_visible_club" on public.club_badges;
create policy "club_badges_select_visible_club"
on public.club_badges for select
to authenticated
using (
  club_id is null
  or exists (
    select 1 from public.clubs c
    where c.id = club_badges.club_id
      and (
        c.visibility = 'open'
        or c.owner_user_id = auth.uid()
        or exists (
          select 1 from public.club_members cm
          where cm.club_id = c.id
            and cm.user_id = auth.uid()
        )
      )
  )
);
