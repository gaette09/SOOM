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

1. My Club Status
2. Weekly Ranking
3. Club Challenge
4. Badge Wall
5. Club Activity Pulse

This order makes Club feel like a living competitive identity space: status first, rank second, action third, achievement fourth, pulse fifth.

Ranking is always scoped to the selected club. v1 does not include a global SOOM leaderboard.

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
- Show top 3, nearby ranks, and the user's rank before a full board.
- Ranking should feel competitive but not hostile.
- Avoid exaggerated winner language.

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

## Mock Foundation v1

v1 can use mock data:

- Mock club home
- Mock joined clubs
- Mock created clubs
- Mock recommended clubs
- Mock weekly rank
- Mock contribution distance
- Mock challenge progress
- Mock badge states
- Mock activity pulse

The Club tab UI foundation should render the blueprint as a real product surface even before backend support:

1. Club Home
   - my clubs, created clubs, joined clubs, recommended clubs, and create club entry
   - club cards show sport, member count, current user's weekly rank when joined, and goal progress
   - recommended clubs are preview-only in v1
2. Selected Club Detail
   - the dashboard opens only after the user taps a club
   - each mock club can have different ranking, challenge, badge, and pulse data
3. My Club Status hero
   - club name, member count, weekly rank, contribution distance, and club goal progress
   - belonging first, numbers second
4. Weekly Ranking
   - distance, activity count, and consistency filters
   - top ranks plus the current user's row
   - highlight "나" without shame copy or aggressive winner language
   - copy should read as "within this club", not a global ranking
5. Challenges
   - progress bars for weekly movement count, club distance goal, and morning movement
   - contribution framing instead of pressure
6. Badge Wall
   - earned, in progress, new this week, and rare states
   - short labels, muted surfaces, no neon game styling
7. Club Activity Pulse
   - compact event rows for badge wins, rank movement, goal progress, and member activity
   - do not repeat Feed workout cards

The empty state should say that the user has no club yet, show recommended clubs, and provide a create club CTA. It should not present Club as an offline meetup board.

Create club v1:

- The entry exists from Club Home.
- Backend creation is deferred.
- Placeholder copy should say: "Club creation is coming soon."

Deferred:

- Real club backend
- Real club creation
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
