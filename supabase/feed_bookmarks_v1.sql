-- SOOM Feed Bookmarks v1
-- Migration foundation only. Do not apply automatically from the app.
-- Scope: private per-user bookmarks for feed posts.

create table if not exists public.feed_bookmarks (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.feed_posts(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (post_id, user_id)
);

create index if not exists feed_bookmarks_post_id_idx on public.feed_bookmarks(post_id);
create index if not exists feed_bookmarks_user_id_idx on public.feed_bookmarks(user_id);

alter table public.feed_bookmarks enable row level security;

-- Deliberately NOT modeled on feed_reactions_select_visible_parent —
-- a bookmark is private. Only the person who saved a post can see
-- that they saved it; nobody else, not even the post's own author,
-- gets to see who bookmarked their post.
create policy "feed_bookmarks_select_owner"
on public.feed_bookmarks for select
to authenticated
using (user_id = auth.uid());

create policy "feed_bookmarks_insert_owner_visible_parent"
on public.feed_bookmarks for insert
to authenticated
with check (
    user_id = auth.uid()
    and exists (
        select 1 from public.feed_posts
        where feed_posts.id = feed_bookmarks.post_id
          and (feed_posts.user_id = auth.uid() or feed_posts.visibility = 'public')
    )
);

create policy "feed_bookmarks_delete_owner"
on public.feed_bookmarks for delete
to authenticated
using (user_id = auth.uid());
