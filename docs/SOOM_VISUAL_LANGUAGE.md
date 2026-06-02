# SOOM Visual Language v1

## Purpose

SOOM should feel like a quiet training companion, not a KPI dashboard. The visual system should help people read their workout life calmly: first the story, then the evidence, then deeper analysis only when they ask for it.

## Color Philosophy

- Use neutral surfaces as the default reading layer.
- Use sport and status colors as small cues, not full-card themes.
- Avoid aggressive red/orange dominance unless the UI truly needs caution.
- Recovery color is a companion cue, not a warning state.
- Feed cards should rarely use more than one accent at a time.

SOOM's product accent is purple:

- Primary accent: `#7541EE`.
- Soft accent surfaces should stay lavender and low-contrast, not saturated purple blocks.
- Purple belongs to selected states, CTAs, progress highlights, active tabs, rank emphasis, and badge accents.
- Body copy remains ink/gray. Do not turn explanatory text purple.
- Green stays available for recovery, nature, route, or sport-specific cues when the meaning is genuinely semantic.
- Bottom Navigation selected state and the central Record action use the purple accent so the app-level interaction language is consistent.
- Feed draft badges, contextual active chips, lightweight CTAs, carousel indicators, Activity selected controls, Profile identity pills, and Club ranking/challenge progress should pull from the shared accent tokens instead of local green or blue.
- `accent`, `accentInk`, `accentSurface`, `accentMuted`, `accentLine`, `selectedSurface`, and `selectedInk` are the app-level accent tokens. New selected, active, CTA, progress, badge, and chip states should use these tokens first.
- Route green is allowed only when the route/map itself is the semantic object, such as Record map polylines or drawn route previews. It should not be used as a generic selected, CTA, ranking, badge, or progress color.
- Recovery/status colors remain semantic. Use them for actual recovery, readiness, caution, warning, or health state meaning, not for generic navigation or product emphasis.

## Typography Hierarchy

Each screen should prefer:

1. One primary headline.
2. One or two supporting metrics.
3. Everything else as secondary reading text.

Feed cards should read like short notes. Large metric typography belongs in workout detail, not feed consumption.

## Card Hierarchy

SOOM uses three visual depths:

- Primary: the main current object or action.
- Secondary: normal repeated cards.
- Ambient: context, hints, lightweight assistant surfaces.

Borders and shadows should stay soft. Separation should come from spacing, muted surfaces, and clear content grouping rather than heavy decoration.

## Feed Rhythm

Feed is the home surface. It should support shallow consumption:

- Person and activity context before KPI.
- One emotional story beat before metrics.
- Empty feed surfaces should feel like a first invitation, not a failure state.
- One short caption.
- One or two metrics.
- One visual route/photo media area.
- One small recovery cue.
- One lightweight social rhythm: tiny reactions or one short encouragement.
- A quiet interaction row.

Workout split, zone, climb, terrain, progression, and recovery impact remain in detail depth.

## Storytelling Philosophy

Feed should feel like a quiet stream of movement stories. The card should first answer what the day felt like, then show just enough evidence to invite detail.

- Lead with emotional context: weather, time of day, route atmosphere, or why the person moved.
- Keep story text reflective, not performative.
- Avoid bragging, self-congratulation, and KPI-first copy.
- Prefer "오늘은 페이스보다 호흡" over "오늘 기록 최고".
- Route mood should be short and concrete: "강변 바람이 좋았던 코스", "비 온 뒤 한강", "조용한 업힐 구간".
- Recovery copy should sound like a companion: "무리하지 않아도 좋아요", not a score alarm.

Story pacing:

1. Header: person and situation.
2. Media: route or photo atmosphere.
3. Story: one reflective sentence.
4. Evidence: one or two light metrics.
5. Context: route/recovery/social cues.

This keeps the feed readable without turning it into a diary or a dashboard.

## Empty State Philosophy

Empty states in SOOM are part of the first journey. They should explain what will appear after the user's first movement without making the app feel unfinished.

- Never lead with cold copy such as "아직 아무도 없어요" or giant zero metrics.
- Prefer warm future-facing copy: "첫 운동이 쌓이면 여기에 리듬이 남아요."
- Offer one to three gentle next steps: import a workout, view a route, find a club, or connect Health.
- Use a quiet surface, subtle icon, and breathing spacing instead of oversized illustrations.
- Seed content can preview a route/story shape, but should not fake social proof or pretend real activity exists.
- Recovery empty copy should say that more movement will help SOOM read the flow, not that the user failed to provide data.
- Profile empty copy should emphasize trust and connection: Health, account, and local-first ownership can be set up gradually.

The first journey tone is "we can start here", not "you need to complete setup".

## Feed Social Tone

SOOM social UI should feel like people noticing each other's rhythm, not competing for attention.

- Start with the person, activity mood, place hint, and club/crew context.
- Use tiny contextual labels such as "같은 루트", "같은 클럽", "비슷한 페이스", "recovery-friendly", or "오늘 추천".
- Reactions are lightweight encouragements, not like counters.
- Avoid large counts, ranking language, viral phrasing, or notification-heavy treatment.
- Micro-comments should stay short and warm, such as "오늘 리듬 좋았네요" or "회복 잘 들어갔어요".
- Club cards should express crew vibe and participation before leaderboard status.

The goal is belonging and gentle participation. A feed card should answer "who moved, what did it feel like, and why might I care?" before it shows deeper analysis.

## Feed Media Rules

Feed workout cards should feel visual before they feel analytical.

- The first media item is a lightweight route preview.
- The media area is the card anchor; it should be taller and more visually present than KPI rows.
- If activity photos exist, they follow the route preview in a horizontal swipe carousel.
- Route and photo previews share one unified media carousel layer.
- A route preview is treated as media, not as a separate map widget or metadata block.
- Every media page should use the same height, corner radius, page indicator, and bottom label treatment.
- Do not mount live Mapbox map views inside repeated feed cards.
- Route previews should use muted drawn polylines, start/end cues, and privacy-safe language.
- Photo previews can use local placeholders until the feed backend provides real image URLs.
- Media can extend close to the card edge, while text, metrics, and actions keep inner padding.
- Avoid full-bleed drama; the media should enrich the card without becoming a hero banner.
- Page indicators should stay tiny and quiet.

Unified carousel rules:

- The sequence is `route -> photo -> photo` when photos exist.
- Route pages and photo pages should feel like equal content moments in the same swipe rail.
- Route-as-media should communicate place, rhythm, and privacy-safe movement atmosphere before map precision.
- Photo-as-media should use the same immersive frame and label grammar as route-as-media.
- The carousel remains lightweight; repeated feed cards must not instantiate live Mapbox maps.

The feed card order is:

1. Header: person, activity mood, time, location or club context.
2. Media carousel: route first, photos second.
3. Story: movement mood, emotional context, and one short reflective line.
4. Context: sport, recovery, route mood, or relevance cue as one emotional grouping.
5. Summary evidence: one or two lightweight metrics.
6. Lightweight reactions or one micro-comment.
7. Interaction row.

## Content Cohesion Rules

Feed cards should not feel like stacked modules. A workout card should read as one small story:

- Header sets who and situation.
- Media gives place and atmosphere.
- Story names the feeling.
- Context chips explain why the card is relevant.
- Metrics quietly support the story.
- Reactions continue the same emotional rhythm.

Avoid hard section dividers inside a feed card. Use spacing, gentle grouping, and one light hairline only where social rhythm needs separation. Recommendation and club cards should stay visually quieter than workout media cards so the feed keeps a human movement anchor.

## Spatial Composition Calibration

The Feed should lean content-first rather than feature-first:

- Show workout story cards before recommendation or coach utility surfaces whenever real feed content exists.
- Let cards sit close to full width while preserving a small native iOS breathing margin.
- The media carousel should be the largest element in a workout card and should feel close to edge-to-edge inside the card.
- Header and utility copy should be shorter than the story/media relationship.
- Large workout cards need generous vertical gaps after them so the scroll feels magazine-like, not dashboard-dense.
- Recommendation and club surfaces may follow the feed, but they should be visually quieter than the workout story cards.

## Immersive Feed Principles

The feed should feel like a calm stream of movement surfaces, not a stack of app widgets:

- Media and story should carry the first impression; controls and labels should recede.
- A workout card can keep a soft surface, but its border should be barely perceptible.
- Route/photo previews should be large enough to create atmosphere before the user reads metrics.
- Media corners can be soft and content-like, with minimal shadow and no heavy frame.
- Start/end route markers should be subtle privacy-safe hints, not map UI controls.
- Utility surfaces such as route recommendations, club prompts, and coach hints should appear after primary feed content.
- Visual silence is intentional: empty space between cards helps each workout feel like a separate moment.

## Editorial Feed Philosophy

Feed should read closer to an editorial movement journal than an exercise dashboard:

- Treat the route/photo carousel as the hero memory of the workout.
- Keep the outer card frame nearly invisible; separation should come from surface tone, media scale, and whitespace.
- Compress the header to the person, a short activity mood, and minimal time context.
- Let one short story sentence carry the emotional point of the card.
- Move KPI rows into the near-background: smaller type, lower contrast, no heavy metric container.
- Keep context chips and reactions quiet enough that they feel like continuation, not separate modules.
- Floating coach should feel present but peripheral, with a subtle companion mark and a secondary score badge.

Editorial cards should still be tappable and scannable, but they should first feel like a remembered movement, then like a record.

## Final Editorial Calibration

The final feed calibration should minimize interface weight:

- Media should carry roughly the dominant visual share of a workout card.
- Header metadata should be compressed enough that the media feels like the first real object.
- Story copy should resolve to one emotional sentence whenever possible.
- KPI evidence should fade into the background and never be the first glance.
- Card boundaries should be almost silent; the feed should feel continuous, not boxed.
- Recommendation, route, and club support surfaces should sit below workout media in hierarchy.
- Floating coach should remain a quiet peripheral companion, with a subtle icon and an even quieter score badge.

This is the "content first, interface later" rule for SOOM Feed.

## Quiet Reduction Pass

SOOM Feed should keep removing interface until only the useful emotional trace remains:

- Keep at most one quiet context cue inside a workout feed card.
- Let route/photo media and one short story sentence carry the card.
- Treat KPI rows as low-contrast evidence, never as a dashboard block.
- Reactions should feel like a small social aftertone, not a second content module.
- Header metadata should only confirm who moved and roughly when.
- Increase vertical pauses between feed items so the scroll feels calm and editorial.
- Floating coach should be visible but peripheral; the score is secondary to the companion presence.

Reduction is a product choice: fewer chips, fewer labels, fewer visible controls, and more confidence in the workout memory itself.

## KPI Compression Principles

Feed metrics are evidence, not the headline:

- Distance, time, pace, and count values should use smaller type than story copy.
- Metric surfaces should be low contrast and grouped as a quiet evidence row.
- Avoid placing metrics directly under the media with high visual weight.
- If a user wants split, climb, terrain, zone, progression, or recovery impact, that belongs in Activity detail.
- A feed card should still make sense if the user reads only the media and story.

## Activity Library Rules

Activity is SOOM's personal workout library:

- Calendar is the anchor, with month/week/list modes and quiet sport color dots.
- Recent changes sit directly under the calendar as a small directional strip.
- Recent workouts use compact library rows, not Feed-size cards, so at least several records can be scanned on one screen.
- Workout rows may borrow Feed's route/photo language, but remove social layers, coach copy, comments, and reactions.
- Missing workout values should be omitted; avoid bug-like labels such as "거리 없음" or "0분" in the library.
- Recent changes should read as direction, not a KPI board: consistency up, recovery steady, time up.
- Favorite routes are memory surfaces, not leaderboards.
- Statistics stay at the bottom and are limited to count, time, and distance.
- Floating Coach is hidden or minimized in Activity because the user's workout shelf should remain unobstructed.

## Activity Detail Rules

Activity Detail is the private interpretation surface for one workout:

- Lead with the route or map memory. The first visual read should be "where this movement happened," not a KPI board.
- Put a compact workout summary directly under the hero: sport, date, distance, duration, pace or speed, and heart rate when available.
- Add a "Today's Rhythm" interpretation before deep data so the workout has meaning before numbers.
- Recovery guidance is private-first. It belongs in Floating Coach, personal recovery surfaces, and Activity Detail, but not in public Feed cards by default.
- Hide empty technical sections. Splits, terrain, elevation, heart rate zones, charts, and route-specific insights should appear only when data exists or an explicit insight is available.
- Use the hierarchy route first, meaning second, numbers third.
- Actions should be clear and quiet: saved state, Feed share draft, and deferred edit/delete controls. Sharing starts as a draft, not an automatic public post.

## Profile Identity Rules

Profile is SOOM's movement identity space:

- Activity answers "what did I do?" Profile answers "what kind of athlete am I?"
- The first Profile viewport should lead with profile image, name, short motto, identity tags, and long-term movement summary.
- Do not put recent workout lists in Profile; those belong in Activity.
- Movement Identity can include representative sport, active days, total distance, total time, and representative route.
- Movement Pattern should describe style, not only numbers: morning rider, recovery-friendly, consistency-centered, weekend long-distance.
- Personal Best should show only representative records, not a full statistics dashboard.
- Favorite Routes in Profile are identity markers; Activity can show the fuller route library.
- Badge Showcase should show 3-5 representative achievements and connect naturally to Club identity.
- Connections and settings sit below identity. HealthKit, Garmin, Strava, account, privacy, and baselines are support surfaces, not the hero.
- Profile can feel more personal and brand-like than Activity, but should remain calm and readable.

## Club Competitive Identity Rules

Club is SOOM's online belonging and contribution space:

- Club should feel more competitive than Feed, more social than Activity, and more compact than Record.
- Lead with My Club Status: club name, weekly rank, contribution, and club goal progress.
- Weekly Ranking is a primary surface, not a hidden detail, but the user's own position must stay easy to find.
- Ranking types should include distance, activity count, consistency, and sport-specific boards.
- Challenges should be collective and contribution-oriented: weekly movement count, club distance goal, recovery-friendly activity, morning movement.
- Badge Wall should reward consistency, contribution, recovery-aware participation, and club identity.
- Club Activity Pulse should summarize movement inside the group: rank changes, badge wins, goal progress, and member activity. Do not repeat Feed cards one-for-one.
- Avoid offline meetup-first UI, event scheduling dashboards, moderation-heavy community tools, or aggressive game styling.
- Visual tone can use clearer progress, ranking, and badge surfaces, but keep SOOM's calm spacing and muted palette.
- The implemented Club foundation uses mock data until backend support exists; the UI should still feel like a joined online club, not a placeholder dashboard.
- Empty Club states should invite users to find a club with a similar rhythm and avoid offline meetup-first language.
- Club should open on a home surface first: my clubs, created clubs, joined clubs, recommended clubs, and create club entry. Ranking surfaces live inside selected club detail.
- Club Detail hierarchy is identity -> visual status -> members -> ranking -> challenges -> badges -> pulse.
- Club Detail must explain identity before ranking, but the explanation should be compact: one intro, one short purpose line, mood tags, rule chips, and member preview.
- Favor graphs over explanatory copy. Club goal, weekly activity, contribution, challenges, and rank position should be shown with rings, bars, stat tiles, avatar cards, and progress cards before paragraphs.
- Member previews should show roles such as owner, top ranked, consistency leader, recent member, or similar pace; avoid turning this into a full directory in v1.
- Purpose and rules should make competition feel bounded and fair before showing the leaderboard, using check cards or compact rule chips instead of long bullet lists.
- Ranking copy must name or imply the selected club scope, such as "SOOM Riders 내 이번 주 랭킹"; avoid global leaderboard language in v1.
- Purple is the Club accent for selected filters, current-user rank, progress bars, badge emphasis, and create/join CTAs. Green remains available only when a specific recovery/nature meaning is needed.
- Create club can be visible as a future-ready CTA, but it should use clear placeholder copy until backend creation exists.
- Join, leave, and manage actions can appear as placeholder states, but backend mutation is not part of v1.

## Chip Rules

- Use at most one or two chips per feed card.
- Chips should be small and muted.
- Chips should explain context, not create alarm.
- Avoid stacking multiple semantic colors in one card.

Examples:

- "회복 친화"
- "리듬 안정"
- "가볍게"
- "같은 루트"
- "같은 클럽"
- "비슷한 페이스"

## Floating Coach Behavior

The Floating Recovery Coach is a companion layer:

- It should not cover the feed hierarchy.
- It should remain dismissible.
- It should use calm material, soft borders, and compact copy.
- Expanded state should summarize, then link to full Recovery detail.
- Minimized state is a circular companion button, not a bottom bar.
- Initial entry can show a short preview for about two seconds, then collapse into the circle.
- Place it at the lower trailing edge above Bottom Navigation so it does not compete with the tab bar.
- The icon can use a subtle companion cue such as sparkles/orbit/wave, but should avoid robot, brain, or chatbot-heavy symbolism.
- A tiny face-like rhythm mark inside a breathing circle is preferred when it feels like SOOM's companion face, not a chatbot avatar.
- Keep the companion mark as the main visual weight. The recovery score remains a tiny secondary badge, not the button identity.
- The circular button should be clear, filled, and legible; companion subtlety must not rely on translucent opacity that makes the icon or score unreadable.
- The sheet uses two intentional states only: compact and expanded. "자세히 보기" expands the same sheet instead of pushing navigation.
- The sheet starts with "회복 코치", then centers one score, one larger status, and one coach sentence. Remove setup/help panels such as "데이터가 적을 때" from this compact companion state.
- Coach text may type in softly when the sheet opens. Characters appear one by one, with a 0.25-0.35 second pause between words for a breathing rhythm. Use one stronger soft impact at each word start, skip spaces/punctuation, and disable typing motion when Reduce Motion is active.

It is not a warning system, modal blocker, or dashboard replacement.

## Profile Identity Surface

Profile is the movement identity surface, not the app's first settings drawer:

- Lead with a Movement Identity Card: avatar, name, handle, one representative identity phrase, one representative badge or emblem, and only then compact supporting stats.
- Profile Hero starts with identity, not metrics. The phrase ("리듬을 지키는 라이더", "회복을 아는 러너", or similar) should be the first emotional read after the user's name.
- Representative badge belongs in the hero as a visible identity marker. Use purple on the badge icon, state, or small accent line, not as a full-card fill.
- Active days, total distance, and representative sport support the identity in one compact row. Current month state and setup status should not lead the hero unless they explain identity.
- Activity owns calendars, recent workouts, workout lists, and workout detail. Profile must not show a recent workout list.
- Movement Pattern should use compact cards or chips for human traits such as morning, recovery-friendly, consistency-centered, or weekend long-distance. Use purple only for representative traits.
- Personal Best is a showcase, not a history table. Keep it to three representative records with value, context, and icon.
- Badge Showcase should show 3-4 representative badges with state/progress and a Club-compatible structure.
- Signature Routes are identity markers. Use route names with meaning labels such as 대표 코스, 회복 루프, or 도전 지점 instead of turning this into Activity's frequency list.
- Connections and Settings live below identity: HealthKit, Strava future, Garmin future, Weather/location permissions, account, ownership, training baselines, privacy, notifications, and app info are support surfaces.
- Empty Profile states should say the user is building their movement rhythm and that the first workout will create representative sport and pattern, without feeling like a setup checklist.

## Record Map Start Surface

Record is not a settings-like list of start options. It is a full-screen pre-workout launch mode.

- Selecting Record from Bottom Navigation opens a full-screen launch surface instead of replacing the current tab content.
- Bottom Navigation and Floating Coach stay hidden while Record launch is open so the start action has no visual competition.
- A back control in the top leading corner returns to Feed by default.
- The map surface is the primary layer. When `MBX_ACCESS_TOKEN` resolves to a usable Mapbox token, Record renders a real Mapbox map; otherwise it falls back to the lightweight drawn map.
- Record's initial camera should favor a close, usable launch scale near a 100m Mapbox scale-bar feel. Do not zoom out just to show every sample route point if that makes the start surface feel less immediate.
- Record must not force a location permission prompt on entry. If location is unavailable, show a subtle fallback/current-area marker and keep the launch flow usable.
- Keep text minimal on the map itself: a top notification header, weather temperature, and the black READY start control are enough by default.
- Record guidance is a separate top header layer, not a floating card inside the map overlay stack. It sits just below the status bar with about `safeAreaTop + 8-14pt` visual top padding, 34-38pt side insets, and a compact 76-82pt height. The header owns the daily recommendation copy: label, recovery state, and one short body line about how to move today.
- Do not show a persistent route strip under the guidance header. Recommended routes are accessed only from the right-edge route icon and route recommendation catalog, so the launch map keeps a single top message instead of stacked information pills.
- Back and right-edge controls belong directly under the compact header, never drifting into the map center or reserving removed route-strip space. Back sits roughly 28-32pt below the header bottom; the right control column starts roughly 10-14pt below it. Use a neutral surface for readability, with `SOOMColor.accent`, `accentInk`, and `accentLine` reserved for the icon, key state, and border.
- Record top controls must use one computed frame source for the guidance banner, back button, and right-edge controls. Avoid separate `padding`, `offset`, or legacy route-strip spacing paths that can make tests and actual render positions diverge.
- Right-edge controls stack in this order: weather, route recommendation, current-location recenter. Weather opens a detail sheet, route opens a mock catalog, and recenter is the only location-permission entry point.
- Controls should sit on corners or edges as small circular icon buttons. Labels are primarily accessibility labels.
- The recenter button icon and the map's current-location marker are separate concepts. Keep the button neutral; the actual map marker uses SOOM purple.
- Mapbox logo/attribution must remain visible and low. Keep ornament bottom inset small enough that logo/info stay near the bottom safe area instead of floating near READY.
- Actual GPS location uses a compact center-anchored purple dot, white ring, soft halo, and small gentle pulse. Keep the pulse around 48-50pt max diameter so it does not cover map detail. Fallback/sample markers stay static or very quiet. Respect Reduce Motion by disabling the pulse.
- Import, HealthKit connection, and device connection controls do not belong on the Record surface; move them to Activity/Profile so Record stays focused on starting.
- Sport mode selection is hidden until the READY long-press gesture. Cycling/running/walking fan out in the upper semicircle only; never place sport choices below READY.
- READY reacts on touch-down by revealing sport icons immediately, but tap-only release is still a no-op. A workout can start only after READY touch/press, visible sport reveal, drag hover, and release while that sport is hovered. Releasing at center, without drag, or outside a sport target cancels the start.
- READY interaction is limited to the visible black circular play button. Do not attach the READY drag gesture to the whole launch control container, wave, gradient, spacer, or a rectangular transparent content shape. Decorative wave, glow, ring, and sport icon layers should not create extra hit area; touches that begin outside the button circle must do nothing.
- Sport icons animate from READY center to the upper semicircle with a small stagger: cycling first, running second, walking third. Hovered sport icons may scale slightly and show an accent ring, but the interaction should stay calm.
- Haptics should mark no-op tap, long press, reveal, hover changes, confirmed release, and cancellation without feeling like a game control.
- The main start button sits near the bottom center as a black primary control floating inside a SOOM-purple bottom field. Render this field with an oversized radial blob placed below the screen, not a custom clipped path, alpha-masked shape, linear gradient, fog, blur, or rectangle stack. The blob frame must be much larger than the screen, with its visual edge created only by radial opacity falloff from bottom-center purple to fully transparent outer edge, so no shape top edge can appear. The blob breathes by animating scale, y-position, and opacity over 3.2s with autoreverse. Reduce Motion keeps a static middle state. The READY control itself is icon-only: a black circular button with centered `play.fill`, no selected sport icon, no "READY" text, and no "길게 눌러 시작" text inside the button. A subtle outer ring may breathe separately from the button surface, but the play icon stays steady. When the user touches/reveals sport choices, the blob moves lower, scales down slightly, and fades to about 0.45 opacity so the map and upper sport icons stay readable. Tap still never starts a workout; release must happen over a hovered sport.
- The breathing blob is always active in idle launch state. READY interaction may temporarily weaken or pause the blob while the sport selector is revealed, but every cancel, tap-only release, selector close, or confirmed start transition must return the wave to idle breathing rather than leaving it frozen.
- Route recommendation is a foundation layer: sample route overlay and mock route catalog first, route/search backend later, and recovery/weather/time-aware recommendations only after the basic flow is stable. Feed cards must not embed live Mapbox maps.
- Record weather, route recommendation, and recovery coach sheets use fixed single-height presentations. The sheet container should not expand or collapse through drag gestures; only the inner `ScrollView` should scroll.

## Motion Principles

Motion should make the app feel alive without making it feel excited.

- Feed cards can reveal with a small fade and short upward movement.
- Press feedback should use subtle scale and opacity, not bounce.
- Floating coach expansion should feel like a calm sheet opening, not an alert.
- Floating coach preview collapse should use a short spring/fade, with no repeated pulsing.
- Respect Reduce Motion by removing reveal/press animation where possible.
- Avoid chained animations that make the feed feel like a dashboard demo.

## Haptic Principles

Haptics are reserved for intentional actions:

- Opening a feed card.
- Expanding or dismissing the floating coach.
- Switching a primary tab.

Use selection or soft impact only. Avoid repeated haptics while scrolling or reading.

## Scroll Rhythm

Feed spacing should create breathing room between ideas:

- Card groups need more vertical spacing than dense dashboards.
- Recommendation surfaces should be tappable but quiet.
- Section headers should explain context briefly, then get out of the way.
- Cards should keep one primary message visible before metrics.

## Dark Mode Notes

SOOM currently keeps Light Mode while the visual system stabilizes. When Dark Mode is revisited:

- Avoid glowing accents.
- Preserve muted separation between background, surface, and ambient cards.
- Keep recovery/status colors below alert intensity.
- Verify feed cards at large Dynamic Type sizes.
- Floating coach material must remain visible without becoming a warning badge.
- Dark surfaces should separate through value and spacing before accent color.

## Anti-patterns

- Giant recovery blocks at the top of Feed.
- Full analysis dashboards inside Feed.
- Multiple large KPI groups per card.
- Strong gradients as default structure.
- Loud competitive color language.
- Chips that look like warnings when they are only context.

## Feed Reference Card Structure

Feed workout cards should read like a clear movement post, not a blurred editorial poster.

Order is fixed:

1. Profile, sport, time, location, one context pill, more action.
2. Title and short body copy.
3. Split media block with route preview and photo preview in the same layer.
4. KPI row with distance, time, average pace or speed, and average heart rate.
5. Tags, reactions, comment preview, and lightweight actions.

Rules:

- Use white or near-white card surfaces with readable ink contrast.
- Do not reduce text opacity until labels become hard to read.
- Route preview should feel like a lightweight map surface with roads, river/park cues, route line, start/end dots, and distance badge.
- Photos and route preview should share the same media block; route is not a separate abstract graph.
- If multiple photos exist, show a small numeric indicator such as "1 / 2".
- Avoid full-card abstract route artwork and editorial blur as the default feed pattern.
- Recovery Coach guidance is private-first and should not appear in public feed cards by default.
- Feed may keep public tags such as "회복 러닝" or "강변", but private recovery scores and coaching sentences belong in Floating Coach, Activity Detail, or personal recovery surfaces.

## Feed Layout Cleanup Rules

Feed is content-first. The bottom tab already names the current destination, so root tab screens should avoid repeating large fixed titles such as "피드", "기록", or "프로필" at the top.

Rules:

- Start Feed with a dismissible coach access banner or the first workout card, not a duplicate page title.
- Keep feed card spacing near 20-28pt so the next card remains visible while scrolling.
- Do not place route recommendations, challenge cards, club cards, or rhythm support blocks at the bottom of Feed by default.
- Move support surfaces to Record, Activity, or Club when they become actionable.
- Coach access copy belongs above the first card when it explains the floating coach.
- Floating coach button icon and score must remain legible; companion subtlety should not mean unreadable opacity.
- Primary text uses clear ink contrast; only metadata may move to secondary gray.

## Share Card System

SOOM share cards are vertical story-first exports. The default ratio is 9:16, with SOOM purple as the app-level accent and quiet off-white surfaces for readable text.

Presentation rules:

- Share controls live in a bottom sheet composer, not embedded inside Activity Detail content.
- Activity Detail should remain workout interpretation-first. It may show `피드에 공유하기` and `이미지로 공유하기`, but not the full card picker, background picker, target grid, or 9:16 preview inline.
- The composer hierarchy is `preview carousel -> background -> targets`.
- The 9:16 preview carousel should be the first visible object in the composer and should be large enough to read without being clipped.
- Share card selection is swipe-first. Avoid making the composer feel like a settings form with a large option grid.
- Transparent preview uses a checkerboard backdrop only in the composer preview. The exported transparent image must remain transparent.

Share Card option rules:

- The UI should say "공유 카드 선택", not "타입 선택".
- `운동 카드`: emotion-first movement card, route/photo background allowed.
- `컨디션 카드`: private-first by default. Public cards must exclude recovery score, personal condition detail, fatigue/readiness language, and sensitive coach guidance.
- `코스 카드`: route-as-content, with privacy-safe start/end masking.
- `클럽 카드`: group rhythm and contribution, not global ranking pressure.
- Card options should include a short preview summary so the user chooses the story, not a technical enum.
- Card selection should stay swipe-first. Do not reintroduce a large type grid unless editing templates becomes a dedicated mode.

Visual card rules:

- Share cards are emotion-first, metric-light story images.
- Use one headline, one interpretation line, and one small supporting mark per card.
- Do not render a heavy dashboard metric grid on the share card itself. Route-based workout cards may use one compact metric row because route + essential data is the expected social workout pattern.
- Workout card copy should read like `10.4km`, `5'02"/km · 52m`, `리듬을 잃지 않은 날`.
- Condition card copy should read condition-first: `좋음`, `82`, `밀어도 되는 날`.
- Avoid technical labels such as Recovery in public-facing primary copy.
- Map/photo cards need a subtle readability overlay; transparent previews use checkerboard only in the composer preview, never in the exported transparent image.
- Every share card includes a quiet SOOM signature footer. Use short brand lines such as `페이스는 숨에서`, `숨부터 잡아라`, `길보다 리듬`, or `함께 쌓은 리듬`; the footer must stay smaller than the main story.
- Signature cards may use a very subtle rhythm/breath background pattern: thin waveform, breathing circle, or route-like curve. It should feel like SOOM's pulse, not a decorative texture.
- Transparent exports do not include the decorative rhythm/breath background pattern or the checkerboard preview surface.
- Route-based workouts should show a clear route line when a route preview payload exists. In workout and route cards, the line is a primary visual, not a background hint.
- Transparent export mode is route/text only: no card surface, no border, no top metadata, no privacy label, no checkerboard, and no decorative rhythm background pattern.
- Sport-specific share metric sets are fixed and privacy-safe: cycling uses distance/time/elevation, running uses distance/pace/time, walking uses distance/time, and fallback uses distance/time.
- Share layouts may vary by route/text placement: route hero, route top with metrics below, route left/text right, centered stats, and transparent overlay. The composer can keep four card types while the model remains ready for layout variants.

Preview/background rules:

- `지도/사진` is the default preview mode and should feel like a shareable memory surface.
- `투명` keeps the export canvas transparent so the card can sit over a story/photo editor background.
- Transparent cards still need enough internal contrast; text should never depend on an unknown external background.
- Composer preview may show a checkerboard and a small `투명` badge to explain transparency. Those elements are preview-only and must not be rendered into exported images.

Target rules:

- Instagram Story, Save Image, and More use the iOS share sheet unless a future native integration is explicitly added.
- Copy Link requires a published remote object and public URL backend, so it should not be exposed in the current UI.
- Share targets should not imply automatic public posting.
