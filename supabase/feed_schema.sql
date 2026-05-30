-- SOOM Feed Backend Foundation v1
-- Draft migration only. Do not apply automatically from the app.

create table if not exists public.feed_posts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    source_workout_id uuid null,
    sport text not null,
    title text not null,
    body text null,
    distance_meters double precision null,
    duration_seconds integer null,
    average_pace_seconds_per_km integer null,
    average_heart_rate integer null,
    route_summary jsonb null,
    visibility text not null default 'private' check (visibility in ('private', 'followers', 'public')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.feed_post_media (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.feed_posts(id) on delete cascade,
    media_type text not null check (media_type in ('route', 'photo')),
    storage_path text null,
    preview_payload jsonb null,
    sort_order integer not null default 0,
    created_at timestamptz not null default now()
);

create table if not exists public.feed_reactions (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.feed_posts(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    reaction_type text not null,
    created_at timestamptz not null default now(),
    unique (post_id, user_id, reaction_type)
);

create table if not exists public.feed_comments (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.feed_posts(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    body text not null check (char_length(body) <= 500),
    created_at timestamptz not null default now()
);

alter table public.feed_posts enable row level security;
alter table public.feed_post_media enable row level security;
alter table public.feed_reactions enable row level security;
alter table public.feed_comments enable row level security;

create policy "feed_posts_select_owner_or_public"
on public.feed_posts for select
to authenticated
using (user_id = auth.uid() or visibility = 'public');

create policy "feed_posts_insert_owner"
on public.feed_posts for insert
to authenticated
with check (user_id = auth.uid());

create policy "feed_posts_update_owner"
on public.feed_posts for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "feed_posts_delete_owner"
on public.feed_posts for delete
to authenticated
using (user_id = auth.uid());

create policy "feed_post_media_select_visible_parent"
on public.feed_post_media for select
to authenticated
using (
    exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_post_media.post_id
          and (feed_posts.user_id = auth.uid() or feed_posts.visibility = 'public')
    )
);

create policy "feed_post_media_insert_owner_parent"
on public.feed_post_media for insert
to authenticated
with check (
    exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_post_media.post_id
          and feed_posts.user_id = auth.uid()
    )
);

create policy "feed_post_media_update_owner_parent"
on public.feed_post_media for update
to authenticated
using (
    exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_post_media.post_id
          and feed_posts.user_id = auth.uid()
    )
)
with check (
    exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_post_media.post_id
          and feed_posts.user_id = auth.uid()
    )
);

create policy "feed_post_media_delete_owner_parent"
on public.feed_post_media for delete
to authenticated
using (
    exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_post_media.post_id
          and feed_posts.user_id = auth.uid()
    )
);

create policy "feed_reactions_select_visible_parent"
on public.feed_reactions for select
to authenticated
using (
    exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_reactions.post_id
          and (feed_posts.user_id = auth.uid() or feed_posts.visibility = 'public')
    )
);

create policy "feed_reactions_insert_authenticated_visible_parent"
on public.feed_reactions for insert
to authenticated
with check (
    user_id = auth.uid()
    and exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_reactions.post_id
          and (feed_posts.user_id = auth.uid() or feed_posts.visibility = 'public')
    )
);

create policy "feed_reactions_delete_owner"
on public.feed_reactions for delete
to authenticated
using (user_id = auth.uid());

create policy "feed_comments_select_visible_parent"
on public.feed_comments for select
to authenticated
using (
    exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_comments.post_id
          and (feed_posts.user_id = auth.uid() or feed_posts.visibility = 'public')
    )
);

create policy "feed_comments_insert_authenticated_visible_parent"
on public.feed_comments for insert
to authenticated
with check (
    user_id = auth.uid()
    and exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_comments.post_id
          and (feed_posts.user_id = auth.uid() or feed_posts.visibility = 'public')
    )
);

create policy "feed_comments_delete_owner_or_post_owner"
on public.feed_comments for delete
to authenticated
using (
    user_id = auth.uid()
    or exists (
        select 1
        from public.feed_posts
        where feed_posts.id = feed_comments.post_id
          and feed_posts.user_id = auth.uid()
    )
);
