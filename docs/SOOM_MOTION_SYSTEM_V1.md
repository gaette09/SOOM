# SOOM Motion System v1

SOOM Motion System v1 defines how movement should feel across Feed, Share, Recovery, Analysis, and future coaching surfaces. Motion should support understanding. It should never compete with workout data, recovery signals, or coaching copy.

## A. Motion Philosophy

SOOM motion is based on the rhythm of movement data: steady, readable, and calm.

Principles:

- Motion should feel like a smooth training rhythm, not a social media bounce.
- Apple Fitness-like stability is more important than playful spectacle.
- Motion should help users understand hierarchy, state changes, and transitions.
- Motion should not delay data reading or make dense fitness information harder to scan.
- Recovery and health-related screens should feel especially grounded and trustworthy.
- Feed and share surfaces may feel a little more expressive, but still avoid aggressive bounce, confetti, or ranking-style celebration.

Avoid:

- Overshooting card bounce
- Fast repeated flashing
- Infinite decorative movement near important metrics
- Motion that suggests urgency, competition, or anxiety
- Surprise movement after the user has started reading

## B. Motion Hierarchy

Motion priority follows information priority.

### Primary Motion

Primary motion is reserved for state changes the user needs to notice.

Examples:

- Share card reveal
- Recovery summary value change
- Daily Readiness state update
- Workout detail sheet position change
- Successful check-in save confirmation

Guidelines:

- Use clear but restrained transitions.
- Prefer fade plus slight vertical movement.
- Keep duration around `normal` or `slow`.
- Use spring only when the object is physically moving, such as a sheet or tab selection.

### Secondary Motion

Secondary motion supports interaction feedback.

Examples:

- Card expand or compact transition
- Feed card tap feedback
- Button press feedback
- Analysis card appearing after load
- Share preview action feedback

Guidelines:

- Keep duration around `quick` or `normal`.
- Press scale should not go below `0.98`.
- Avoid bouncy social reactions.

### Background Motion

Background motion should be rare and subtle.

Examples:

- Slow loading fade
- Subtle shimmer in skeleton states
- Gentle pulse for live or processing states

Guidelines:

- Use only when a state is temporary.
- Do not animate near paragraphs, chart labels, or score explanations.
- Always provide a no-motion fallback.

## C. Timing Tokens

SOOM uses simple timing tokens first. More specialized tokens can be added after repeated use cases appear.

| Token | Value | Use |
| --- | ---: | --- |
| quick | 120ms | Button press, small opacity change |
| normal | 200ms | Card reveal, row update, small state change |
| slow | 320ms | Screen section entrance, score interpolation, share card reveal |
| background | 800ms | Loading shimmer or subtle pulse only |

Curve policy:

- Default to ease-out.
- Use ease-in-out only for paired transitions where entering and leaving both matter.
- Use spring sparingly for physical UI such as bottom sheets, liquid tab selection, and drag release.
- Avoid bounce-heavy curves.

Swift token reference:

- `SOOMMotion.Duration.quick`
- `SOOMMotion.Duration.normal`
- `SOOMMotion.Duration.slow`
- `SOOMMotion.Scale.pressed`
- `SOOMMotion.Offset.cardRevealY`
- `SOOMMotion.normalEaseOut`
- `SOOMMotion.subtleSpring`

## D. Feed Motion

Feed motion should make the list feel alive without turning it into a social dopamine loop.

Guidelines:

- Feed cards may enter with fade plus slight upward motion.
- Avoid infinite scroll jitter or staggered animation that delays scanning.
- Refresh states should be calm and short.
- Feed card tap feedback should be subtle: scale no smaller than `0.98`.
- Do not animate likes, rankings, or competitive reactions in v1 because Feed is growth-sharing, not leaderboard-driven.

Recommended pattern:

- Initial card appearance: opacity `0 → 1`, y offset `8 → 0`, duration `200ms`
- Tap: scale `1 → 0.98 → 1`, duration `120ms`
- Refresh: short fade, no bounce

## E. Recovery Motion

Recovery motion should feel especially trustworthy.

Guidelines:

- Recovery score changes should interpolate smoothly.
- Gauge/ring movement should be slow enough to read.
- Pulse animation, if used, must be subtle and optional.
- Avoid urgent red flashing or repeated alerts.
- Explanation and recommendation cards should appear calmly after data load.

Recommended pattern:

- Score/ring update: smooth interpolation, around `320ms`
- Insight card reveal: fade plus y offset `4 → 0`, around `200ms`
- Loading to loaded: crossfade, avoid layout jump

## F. Share Card Motion

Share card motion should make export feel polished without making the card feel like a template ad.

Guidelines:

- Share card preview can reveal with a calm fade and small upward motion.
- Export should use a brief disabled/loading state, then fade into the share sheet.
- Native share sheet transition should remain the primary system motion.
- Do not animate card contents independently during export; the rendered image should be stable.

Recommended pattern:

- Preview reveal: opacity `0 → 1`, y offset `8 → 0`, duration `320ms`
- Export button feedback: scale `0.98`, duration `120ms`
- Render completion: short fade or state text update

## G. Interaction Rules

Interaction should be responsive but not jumpy.

Rules:

- Tap scale should not go below `0.98` for cards and primary actions.
- Small icon buttons may use `0.99` when visual density is high.
- Swipe interactions should have resistance and a clear settled state.
- Long press should be rare and never required for primary workflows.
- Card shadows should not animate dramatically.
- Haptics should be light and used only for meaningful selection, save, or tab changes.
- Movement should communicate state, not decorate the screen.

## H. Accessibility

Motion must respect user comfort and readability.

Requirements:

- Respect Reduce Motion.
- Provide no-motion fallback for all non-essential movement.
- Avoid fast blinking, repeated pulsing, or high-contrast flashes.
- Do not rely on animation alone to communicate state.
- Loading and completion states must also be expressed through text, layout, or accessibility values.

Reduce Motion fallback examples:

- Replace card slide with opacity-only fade.
- Replace score interpolation with immediate value update.
- Replace shimmer with static placeholder.
- Replace pulse with a stable status label.

## Implementation Boundary

v1 defines the language and tokens. It does not require applying motion across every screen.

Allowed now:

- Document motion principles.
- Add small token definitions.
- Use tokens in future focused UI polish tasks.

Deferred:

- Global animation refactor
- Feed scroll animation system
- Recovery gauge animation rewrite
- Share export transition overhaul
- Snapshot/UI animation tests


## Feed Motion Polish v1 Status

Feed Motion Polish v1 applies the motion language to the local mock Feed without changing Feed data, Share card builders, Recovery, or Growth logic.

Implemented behavior:

- Feed items reveal with opacity and a small upward offset.
- The reveal uses a very small stagger so the list does not jump in as one block.
- Reduce Motion removes the offset/animation and keeps the content immediately readable.
- Feed item press feedback uses a subtle scale no smaller than `0.98`.
- Visibility badges remain subtle preview cues and should not imply production permission enforcement.

Still deferred:

- Infinite scroll motion
- Pull-to-refresh motion
- Feed-to-detail transition
- Server-backed feed state changes
