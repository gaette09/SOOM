# SOOM Profile Identity Blueprint v1

## Definition

Activity answers:

> What did I do?

Profile answers:

> What kind of athlete am I?

Profile is not a settings page first. It is the user's long-term movement identity: how they move, what they return to, what they have achieved, and which connections support that identity.

## Recommended Structure

1. Movement Identity Card
2. First journey state when data is sparse
3. Movement Pattern
4. Personal Best
5. Badge Showcase
6. Signature Routes
7. Connections
8. Account and Settings support area

The implemented v1 hierarchy is identity -> pattern -> PB -> badges -> signature routes -> connections/settings. Settings are still available, but they are support surfaces below the athlete identity layer.

## Profile Hero

Purpose:
Make the user immediately recognizable as a mover.

Content:

- Profile image
- Name
- Handle
- Representative identity phrase
- Representative badge or identity emblem
- Account state
- Compact supporting stats: moved days, total distance, representative sport

Example copy:

- 지환
- 리듬을 지키는 라이더
- 대표 뱃지: 30일 리듬
- 128일 움직임 · 1,240km · 자전거 중심

Rules:

- Profile can carry more brand emotion than Activity.
- The hero starts with the identity phrase, not metrics.
- One representative badge belongs in the hero because it makes identity visible before cumulative numbers.
- Stats support identity. Keep them compact and secondary, with 2-3 items at most.
- Keep the intro short and tied to SOOM language: breath, rhythm, 기준, 유지, or 무너지지 않기.
- Do not start with settings.
- Do not show a recent workout list in Profile. Activity owns recent workouts and detailed workout cards.

## Movement Identity

Purpose:
Summarize the user's whole movement life.

Recommended metrics:

- Representative sport
- Active days
- Total distance
- Total movement time
- Representative route

Rules:

- This is cumulative identity, not recent history.
- Avoid recent workout cards.
- Avoid overloading with all possible stats.
- In v1, identity is derived from `UnifiedWorkoutStore` aggregate data when local workouts exist.
- Record-saved distance and route workouts feed the aggregate distance, active days, representative sport, and PB foundation.
- Distance-less/time-only workouts still count toward workout count, active days, and total time.

## Movement Pattern

Purpose:
Describe style and habit.

Example patterns:

- Morning rider
- Recovery-friendly
- Consistency-centered
- Weekend long-distance

Rules:

- Pattern labels should feel human.
- Pattern labels are partially aggregate-driven in v1: morning ratio, consistency, weekend long tendency, and dominant sport can shape the cards.
- Intensity/recovery-friendly classification remains foundation-level until richer effort data exists.
- Do not make the user feel judged.
- Use compact cards or chips. Purple accent is reserved for the primary/representative patterns.

## Personal Best

Purpose:
Show representative peaks.

Examples:

- Longest Ride
- Longest Run
- Fastest 10 km
- First Century

Rules:

- Show only representative records, with a max of 3 in the primary showcase.
- v1 uses aggregate values for longest ride, longest run, and best weekly distance.
- Full workout history stays in Activity.
- Detailed analysis stays in workout detail.

## Signature Routes

Purpose:
Show routes as identity markers.

Examples:

- 한강 북단
- 탄천
- 북악

Rules:

- Profile shows the routes that describe the person.
- Activity can show more complete route history.
- Avoid frequency-first language when it makes this feel like Activity. Use marker words such as 대표 코스, 회복 루프, or 도전 지점.

## Badge Showcase

Purpose:
Connect Profile identity to Club achievement.

Examples:

- 1000 km
- 30 days
- First Century

Rules:

- Show 3-5 badges.
- Do not render a full badge inventory here.
- Rare and new badges can be highlighted, but keep the tone calm.
- Badge cards should show status/progress visually so they can connect to Club later without becoming a full badge engine.
- v1 can reflect simple aggregate thresholds such as first workout, 30 active days, and 1000 km.

## Connections

Purpose:
Support identity without becoming the page.

Content:

- HealthKit
- Garmin future
- Strava future
- Account/settings entry

Rules:

- Connections live near the bottom.
- Settings are support surfaces.
- Profile should not open as a checklist.
- HealthKit, Strava future, Garmin future, and Weather/location permissions belong together as support connections, not hero content.

## Boundary With Activity

Activity:

- Workout list
- Calendar
- Recent workouts
- Workout detail
- Route history

Profile:

- Identity
- Cumulative summary
- Patterns
- Representative records
- Representative routes
- Badges
- Connections
- Account/settings support

## Empty / New User State

New users should not see a broken settings page. Use copy such as:

- 아직 나의 운동 리듬을 만드는 중
- 첫 운동을 기록하면 대표 종목과 성향이 생겨요

The empty state should point toward first movement and trust setup without making Profile feel like a setup checklist.

## Deferred

- Real movement identity classifier
- Real badge engine
- External Garmin/Strava connections
- Editable profile bio/avatar
- Public profile sharing
- Signature route aggregation from persisted route identity
