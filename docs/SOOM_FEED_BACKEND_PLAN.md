# SOOM Feed Backend Plan

## Scope

SOOM Feed Backend Foundation v1 prepares the database and Swift repository boundary for a future Supabase-backed feed. It does not apply migrations, upload photos, sync local workouts, or replace the current mock feed.

The current app keeps a local-first fallback: if Supabase is unconfigured, remote fetch is not implemented, or the network fails, Feed can continue to render `FeedMockData`.

## Tables

- `feed_posts`: the main post record for a workout story.
- `feed_post_media`: route previews and photo media attached to a post.
- `feed_reactions`: lightweight encouragement reactions.
- `feed_comments`: short comments.

The SQL draft lives in `supabase/feed_schema.sql`.

## Privacy Policy

- New posts default to `private`.
- HealthKit-imported workouts are never published automatically.
- Workout-to-feed conversion should create a draft first.
- Public visibility must be an explicit user choice.
- Recovery score, Recovery Coach guidance, fatigue warnings, readiness, and other private recovery data are not stored in feed tables.
- Route summaries should be preview-safe and should not expose raw GPS replay by default.

## Repository Boundary

Swift now has a small Feed backend boundary:

- `FeedPostDTO`: Supabase row model for `feed_posts`.
- `FeedPostMediaDTO`: row model for route/photo media.
- `FeedReactionDTO` and `FeedCommentDTO`: lightweight social row models.
- `FeedRepositoryProtocol`: app-facing feed repository contract.
- `SupabaseFeedRepository`: Supabase-ready repository boundary. v1 refuses remote fetch until a concrete fetcher is added.
- `FeedDataSource`: tries remote when available and falls back to mock feed safely.

## Local Feed Share Draft Flow

Record save can now create a local feed share draft after the workout is stored on device. The flow is explicit:

1. User stops a Record workout.
2. User saves the workout locally.
3. User chooses `피드에 공유하기` or `나중에`.
4. `피드에 공유하기` creates a local draft from the saved `UnifiedWorkout`.
5. Feed can render the draft with an `초안` label through the same card structure.

Draft rules:

- No automatic public sharing.
- Default visibility is `draft` / private-only.
- No Supabase write is performed in v1.
- Recovery score, Recovery Coach guidance, readiness, and fatigue cues are not copied into the draft.
- Photo attach, title/body editing, public visibility, and remote publish remain future scope.

## Future Steps

1. Draft edit screen for title/body/media.
2. User reviews title/body/media before publishing.
3. Photo upload uses Supabase Storage.
4. Reactions and comments are persisted through scoped APIs.
5. Follow graph and club graph determine feed visibility.
6. Moderation/reporting policies are added before broad public feed rollout.
7. User ownership migration remains separate from feed publication.

## Deferred

- No Supabase migration is applied in v1.
- No photo upload/download implementation.
- No live comments or reaction API.
- No feed ranking algorithm.
- No cloud sync for HealthKit or local workouts.
- No RecoveryCalculator, Workout, or Growth logic changes.
