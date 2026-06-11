# Task 0005: Feed Home V1

## Goal

Implement the SOOM Feed Home V1 layout based on:

- `docs/specs/SOOM_MASTER_SPEC.md`
- `docs/specs/SOOM_GOLDEN_SCREENS.md`

Feed Home V1 should make the feed the primary entry screen and express SOOM's core feed philosophy: users open it to see exercise and close it wanting to exercise.

## Required Reading

Read both spec files before implementation:

- `docs/specs/SOOM_MASTER_SPEC.md`
- `docs/specs/SOOM_GOLDEN_SCREENS.md`

Implementation must not conflict with the product direction, golden screen rules, or feed philosophy in those documents.

## Requirements

- Feed Home must be the primary entry screen.
- Add a compact Weekly Snapshot section at the top.
- Weekly Snapshot should include:
  - Weekly workout time
  - Weekly distance
  - Weekly workout count
  - Small weekly graph placeholder
- Add Strava-style workout feed cards.
- Feed cards should support:
  - User profile
  - Workout title
  - Distance
  - Time
  - Average speed
  - Heart rate
  - PR count
  - Map/photo placeholder
  - AI one-line summary
- Use encouragement actions, not likes:
  - 🔥 나도 타야겠다
  - 💪 응원한다
  - 💬 댓글
- Include at least one AI Discovery card.
- AI Discovery must not be more prominent than friend workout cards.
- Keep backend mocked/local only.
- Do not make Supabase changes.
- Do not make OpenAI/API calls.
- Do not do TestFlight/Fastlane work.
- Do not commit.

## Product Notes

- Feed priority is:
  1. Friend workouts
  2. Club activity
  3. AI Discovery
  4. Challenges
- If a workout has a photo, the feed card should prioritize the photo.
- If a workout has no photo, the feed card should prioritize the map.
- The feed should stay centered on workouts, not generic social content.
- Likes are intentionally excluded; SOOM uses encouragement-based actions.

## Acceptance Criteria

- Feed Home V1 layout is visible in the app.
- Existing Record flows are not broken.
- Existing Recovery flows are not broken.
- Existing build still succeeds.
- `xcodebuild` build passes.
