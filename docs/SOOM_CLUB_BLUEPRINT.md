# SOOM Club Competitive Identity Blueprint v1

## Overall Definition

Club is SOOM's online workout club surface.

It is not an offline meetup board. It is where a user sees where they belong, how they are contributing, how they rank this week, which badges they are earning, and which shared challenges need one more effort.

## Product Role

Club should answer:

- Which club am I part of?
- Where am I this week?
- What did I contribute?
- What can I help the club finish?
- What badge or achievement is within reach?
- What changed inside the club today?

Club should not become:

- Offline meetup recruitment first
- Venue, time, or event logistics first
- A complex community management tool
- A duplicate Feed made of the same workout cards

## IA Overview

Club tab order:

1. Club Home
2. Selected Club Detail

Club Home should show:

- My clubs
- Clubs I created
- Joined clubs
- Recommended clubs
- Create club entry

The ranking dashboard belongs inside a selected club. The Club tab should not open directly into a single club's leaderboard, because users can join multiple clubs and create their own clubs.

Selected Club Detail order:

1. Club Identity Hero
2. Visual Club Status
3. Club Purpose and Rules
4. Member Preview
5. Weekly Ranking
6. Club Challenge
7. Badge Wall
8. Club Activity Pulse

This order makes Club feel like a living competitive identity space: status first, rank second, action third, achievement fourth, pulse fifth.

Ranking is always scoped to the selected club. v1 does not include a global SOOM leaderboard.

## Purple Accent And Graph-first Direction

Club uses SOOM purple as its competitive accent:

- Selected ranking filters
- Current-user rank emphasis
- Club goal ring
- Challenge progress bars
- Badge emphasis
- Create/join/manage CTAs

Green remains a supporting semantic color for recovery or nature-oriented meaning. It should not be the default Club accent.

Club Detail should prefer visual comparison over explanatory copy:

- Goal percent appears as a ring or progress graph.
- Member count, active members, and my rank appear as compact stat tiles.
- Rules appear as small check cards or chips, not long bullets.
- Member preview appears as avatar cards.
- Ranking starts with bars/podium-style comparison before rows.
- Challenges are progress cards.
- Badges are short visual cards with state chips.

The hierarchy is:

1. Identity
2. Visual status
3. Members
4. Ranking
5. Challenges
6. Badges
7. Pulse

## Club Identity Layer

Club Detail must explain the club before showing competition.

Recommended content:

- Club name
- One-line introduction
- Club purpose
- Sport type
- Member count
- Public/private state
- Owner or operator
- Active members this week
- Mood tags
- Membership action state

Example:

- SOOM Riders
- "A riding club that builds consistency before speed"
- Purpose: Move lightly at least three times a week
- Cycling · 412 members · public club
- Operator: Jihwan
- 128 active this week

Rules:

- Put identity before ranking.
- Use short, clear copy.
- Make the user understand why this club exists.
- Do not make Club Detail feel like a generic leaderboard page.

## Club Purpose And Rules

Purpose and rules should appear before ranking.

Example rules:

- Consistency over harsh competition
- Participation rate over weekly distance
- Recovery rides count
- No manipulated records
- Respect each member's pace
- Only public feed workouts count toward ranking

This layer keeps competition bounded and explains what kind of contribution the club values.

Presentation rule:

- Keep the purpose to one or two lines.
- Convert rules into compact check cards or chips.
- Avoid explanatory paragraphs such as "look at the club standard before ranking" when the layout already communicates that order.

## Member Preview

Club Detail should include a compact member preview:

- Owner/operator
- Top ranked members
- Consistency leader
- Recently joined member
- Members with similar pace when available

This should be an identity preview, not a full member directory.

## My Club Status

Purpose:
Show the user's current club identity and weekly position at a glance.

Recommended content:

- Club name
- This week's rank
- Weekly contribution
- Club goal progress
- Small rank movement cue

Example:

- SOOM Riders
- This week: 12th
- Contribution: 42.6 km
- Club goal: 68%
- Movement: +2 places

Design notes:

- This is the Club hero, but it should stay compact.
- Use one strong progress surface and one rank cue.
- Do not show a large motivational paragraph.

## Weekly Ranking

Purpose:
Make the user's club position visible and encourage return loops.

Ranking modes:

- Distance ranking
- Activity count ranking
- Consistency ranking
- Sport-specific ranking

Rules:

- Keep the user's row sticky or visually highlighted.
- Show a top comparison graph, compact podium, or horizontal bars before a long list.
- Use SOOM purple for "me" and selected ranking mode.
- Show top 3, nearby ranks, and the user's rank before a full board.
- Ranking should feel competitive but not hostile.
- Avoid exaggerated winner language.

## Club Motivation Layer

Club Detail should not stop at "where am I ranked?" It should also answer "why should I stay here this week?"

The local-first domain layer includes `ClubMotivationSummary`:

- current rank
- previous rank
- rank delta
- weekly contribution distance and count
- contribution percent toward the club goal
- next rank target
- active members this week
- new badges this week
- completed challenges this week
- club goal progress
- one short motivation line

Presentation rules:

- Show rank movement as a calm cue, not a shame mechanic.
- Show contribution as belonging: "I helped fill this club goal."
- Show the next achievable step, such as "11위까지 3.4km".
- Keep the motivation layer compact and close to the hero/ranking area.
- If rank drops or is unavailable, use language such as "이번 주는 숨 고르는 중" or "첫 기여를 시작해보세요".
- Motivation summaries are local-first in v1. Supabase persistence and real ranking algorithms are deferred.

Next Goal Card:

- Appears near ranking.
- Converts the selected ranking metric into a small next action.
- Distance ranking may use remaining kilometers.
- Workout count may use one more session.
- Consistency may use one more day or score step.
- The card should feel achievable, never punitive.

## Club Challenge

Purpose:
Convert belonging into action.

Challenge types:

- Move 3 times this week
- Fill 1,000 km as a club
- Recovery ride/run challenge
- Morning movement challenge

Rules:

- Use progress bars and contribution cues.
- Every challenge card should show a remaining action label.
- Examples: "2회 운동 남음", "12.4km 남음", "3일 더 유지", "목표 달성까지 27%".
- Pair progress with one next action line so the user sees what to do next, not only how far the bar has moved.
- Show what one more workout would add.
- Default to opt-in or low-pressure participation.
- Avoid making recovery-friendly users feel behind.

## Badge Wall

Purpose:
Give club identity a collectible layer without turning SOOM into a game.

Badge states:

- Earned
- In progress
- New this week
- Rare

Badge themes:

- Consistency
- Contribution
- Recovery-aware participation
- Sport identity
- Club role identity

Rules:

- Badges should be clear and calm.
- Rare badges can feel special, but not flashy.
- Badge copy should be short.

## Club Activity Pulse

Purpose:
Show what changed in the group without duplicating Feed.

Pulse examples:

- Mina moved into 3rd for consistency
- Club goal reached 68%
- 4 members earned Morning Start
- Weekend distance ranking changed

Rules:

- Use compact event rows.
- Do not render full workout cards here.
- Link to detail only when the update is meaningful.

## Visual Direction

Club is:

- More competitive than Feed
- More social than Activity
- More compact than Record
- More structured than Profile

Visual surfaces:

- Rank rows
- Progress bars
- Badge chips
- Challenge cards
- Pulse rows

Tone:

- Clear
- Energetic
- Contribution-centered
- Still calm enough to belong to SOOM

Avoid:

- Aggressive game UI
- Heavy neon badges
- Notification overload
- Leaderboard shame

## Local-first Domain Foundation v1

v1 now uses local-first domain data instead of view-local mock arrays. The UI still renders a mock-like product surface, but data flows through Club domain models and a service boundary.

Domain objects:

- `Club`
- `ClubMember`
- `ClubChallenge`
- `ClubRankingEntry`
- `ClubBadge`
- `ClubDetail`
- `ClubDirectorySnapshot`

Service boundary:

- `ClubService` owns directory, detail, create, join, leave, ranking, and challenge fetch operations.
- `InMemoryClubService` remains the local fallback implementation.
- `SupabaseClubService` is the remote foundation for club directory, detail, create, join, and leave.
- `ClubServiceResolver` chooses Supabase first only when Supabase is configured and a remote user id is available, then falls back to local service on failure.
- `ClubsViewModel` is the UI-facing store.
- Invite graph, moderation, real ranking, and challenge progress engines are deferred.

The Club tab UI foundation should render the blueprint as a real product surface even before backend support:

1. Club Home
   - my clubs, created clubs, joined clubs, recommended clubs, and create club entry
   - club cards show sport, member count, current user's weekly rank when joined, and goal progress
   - recommended clubs can open detail and can be joined locally in v1
2. Selected Club Detail
   - the dashboard opens only after the user taps a club
   - each mock club can have different ranking, challenge, badge, and pulse data
3. Club Identity Hero
   - introduction, sport, privacy, owner, active members, mood tags, and visual goal progress
4. Purpose and Rules
   - short club goals and compact rule chips before ranking
5. Member Preview
   - owner, leaders, recent members, and similar rhythm members as avatar cards
6. Visual Club Status
   - member count, active members, weekly rank, contribution distance, and club goal progress
   - belonging first, numbers second
7. Weekly Ranking
   - distance, activity count, and consistency filters
   - horizontal graph or podium-style comparison before rows
   - top ranks plus the current user's row
   - highlight "나" without shame copy or aggressive winner language
   - copy should read as "within this club", not a global ranking
8. Challenges
   - progress bars for weekly movement count, club distance goal, and morning movement
   - contribution framing instead of pressure
9. Badge Wall
   - earned, in progress, new this week, and rare states
   - short labels, muted surfaces, no neon game styling
10. Club Activity Pulse
   - compact event rows for badge wins, rank movement, goal progress, and member activity
   - do not repeat Feed workout cards

The empty state should say that the user has no club yet, show recommended clubs, and provide a create club CTA. It should not present Club as an offline meetup board.

Create club v1:

- The entry exists from Club Home.
- Name, purpose, sport focus, and visibility are captured as `ClubCreateInput`.
- When Supabase is configured and a remote user is signed in, create maps to a `clubs` insert and an owner `club_members` insert.
- If remote creation fails, the local service adds the created club to `createdClubs`.

Join/leave v1:

- Recommended clubs can be joined through `club_members` insert when Supabase is available.
- Joined clubs can be left through `club_members` delete unless they are owned clubs.
- Member count and membership state map from remote membership rows when available.
- Local persistence remains the fallback overlay for created clubs and join/leave state.
- User-facing copy should say the club is saved on this device, not expose `local-first`, `mock`, `backend`, or `remote sync` terminology.

## Club Supabase Foundation

The SQL foundation lives in `supabase/club_foundation_v1.sql`. It is a migration draft only and should not be applied automatically by the app.

Tables:

- `clubs`: club identity, owner, sport focus, visibility, timestamps
- `club_members`: user membership and role
- `club_challenges`: challenge catalog foundation
- `club_badges`: badge catalog foundation

Runtime strategy:

- Supabase configured + signed-in remote user: use `SupabaseClubService` first.
- Remote failure, missing configuration, or no remote user: use `InMemoryClubService`.
- Ranking rows are still derived as a display foundation; no real ranking algorithm exists in this pass.
- Challenge progress remains catalog-level; no progress engine exists in this pass.

## Club RLS Hardening v1

`club_members` RLS no longer uses a direct self-reference. Membership checks are routed through `SECURITY DEFINER` helpers:

- `public.is_club_member(target_club_id uuid)`
- `public.is_club_owner(target_club_id uuid)`
- `public.is_club_admin(target_club_id uuid)`

Policy direction:

- Open club metadata is readable by authenticated users.
- Member lists are scoped to the current user's row, club members, owners, and admins.
- Club update/delete is owner-only in v1.
- Challenge and badge writes are owner-only in v1.
- Admin write privileges remain deferred until column-level constraints or RPC boundaries are designed.

Review note: see `docs/SOOM_CLUB_SUPABASE_RLS_REVIEW.md`.

Deferred:

- Invite/member management
- Real rank calculation
- Badge engine
- Challenge persistence
- Member graph
- Club moderation

## Privacy And Boundary

Club should not automatically publish private workout details.

Rules:

- Feed posts and Club contribution are separate concepts.
- A workout can contribute aggregate distance/count without exposing route details.
- Route start/end privacy masking remains required for shared route surfaces.
- Recovery score and private coach guidance do not appear in Club ranking by default.
