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

-- SECURITY DEFINER helpers avoid self-referencing RLS recursion in policies.
-- Keep these functions narrow, stable, and bound to public search_path.
-- They use auth.uid() only and should be owned by a trusted migration owner.
create or replace function public.is_club_member(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.club_members cm
    where cm.club_id = target_club_id
      and cm.user_id = auth.uid()
  );
$$;

create or replace function public.is_club_owner(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.clubs c
    where c.id = target_club_id
      and c.owner_user_id = auth.uid()
  )
  or exists (
    select 1
    from public.club_members cm
    where cm.club_id = target_club_id
      and cm.user_id = auth.uid()
      and cm.role = 'owner'
  );
$$;

create or replace function public.is_club_admin(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_club_owner(target_club_id)
  or exists (
    select 1
    from public.club_members cm
    where cm.club_id = target_club_id
      and cm.user_id = auth.uid()
      and cm.role = 'admin'
  );
$$;

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

drop trigger if exists clubs_set_updated_at on public.clubs;
create trigger clubs_set_updated_at
before update on public.clubs
for each row
execute function public.set_updated_at();

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
  or public.is_club_member(id)
);

drop policy if exists "clubs_insert_owner" on public.clubs;
create policy "clubs_insert_owner"
on public.clubs for insert
to authenticated
with check (owner_user_id = auth.uid());

drop policy if exists "clubs_update_owner_admin" on public.clubs;
drop policy if exists "clubs_update_owner" on public.clubs;
create policy "clubs_update_owner"
on public.clubs for update
to authenticated
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

drop policy if exists "clubs_delete_owner" on public.clubs;
create policy "clubs_delete_owner"
on public.clubs for delete
to authenticated
using (owner_user_id = auth.uid());

drop policy if exists "club_members_select_scoped" on public.club_members;
create policy "club_members_select_scoped"
on public.club_members for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_club_member(club_id)
  or public.is_club_admin(club_id)
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
        or public.is_club_member(c.id)
      )
  )
);

drop policy if exists "club_challenges_insert_owner" on public.club_challenges;
create policy "club_challenges_insert_owner"
on public.club_challenges for insert
to authenticated
with check (public.is_club_owner(club_id));

drop policy if exists "club_challenges_update_owner" on public.club_challenges;
create policy "club_challenges_update_owner"
on public.club_challenges for update
to authenticated
using (public.is_club_owner(club_id))
with check (public.is_club_owner(club_id));

drop policy if exists "club_challenges_delete_owner" on public.club_challenges;
create policy "club_challenges_delete_owner"
on public.club_challenges for delete
to authenticated
using (public.is_club_owner(club_id));

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
        or public.is_club_member(c.id)
      )
  )
);

drop policy if exists "club_badges_insert_owner" on public.club_badges;
create policy "club_badges_insert_owner"
on public.club_badges for insert
to authenticated
with check (club_id is not null and public.is_club_owner(club_id));

drop policy if exists "club_badges_update_owner" on public.club_badges;
create policy "club_badges_update_owner"
on public.club_badges for update
to authenticated
using (club_id is not null and public.is_club_owner(club_id))
with check (club_id is not null and public.is_club_owner(club_id));

drop policy if exists "club_badges_delete_owner" on public.club_badges;
create policy "club_badges_delete_owner"
on public.club_badges for delete
to authenticated
using (club_id is not null and public.is_club_owner(club_id));

-- Rollback reference:
-- drop policy if exists "club_badges_delete_owner" on public.club_badges;
-- drop policy if exists "club_badges_update_owner" on public.club_badges;
-- drop policy if exists "club_badges_insert_owner" on public.club_badges;
-- drop policy if exists "club_badges_select_visible_club" on public.club_badges;
-- drop policy if exists "club_challenges_delete_owner" on public.club_challenges;
-- drop policy if exists "club_challenges_update_owner" on public.club_challenges;
-- drop policy if exists "club_challenges_insert_owner" on public.club_challenges;
-- drop policy if exists "club_challenges_select_visible_club" on public.club_challenges;
-- drop policy if exists "club_members_delete_self_non_owner" on public.club_members;
-- drop policy if exists "club_members_insert_join_open" on public.club_members;
-- drop policy if exists "club_members_select_scoped" on public.club_members;
-- drop policy if exists "clubs_delete_owner" on public.clubs;
-- drop policy if exists "clubs_update_owner" on public.clubs;
-- drop policy if exists "clubs_update_owner_admin" on public.clubs;
-- drop policy if exists "clubs_insert_owner" on public.clubs;
-- drop policy if exists "clubs_select_open_or_member" on public.clubs;
-- drop trigger if exists clubs_set_updated_at on public.clubs;
-- drop function if exists public.set_updated_at();
-- drop function if exists public.is_club_admin(uuid);
-- drop function if exists public.is_club_owner(uuid);
-- drop function if exists public.is_club_member(uuid);
-- drop table if exists public.club_badges;
-- drop table if exists public.club_challenges;
-- drop table if exists public.club_members;
-- drop table if exists public.clubs;
