# SOOM TestFlight QA

Purpose: manual QA checklist for the first internal TestFlight build. This plan focuses on user-visible flow quality, not new feature development.

## Record

- Open Record and confirm fullscreen map launch appears.
- Tap READY once. Expected: no workout starts.
- Long-press READY. Expected: sport selector appears.
- Drag to cycling/running/walking and release. Expected: workout starts with selected sport.
- Release without hovering a sport. Expected: no workout starts.
- Tap current location. Expected: permission prompt appears only after user action if needed.
- Deny location. Expected: time-only workout can still be started and saved.
- Grant location. Expected: current location recenter and route capture foundation can run.
- Confirm weather pill shows live weather when key/location/network are available.
- Disconnect network and retry weather. Expected: app keeps product-language weather state.
- Stop workout and save. Expected: Activity shows the saved workout.
- Save with no route. Expected: no ugly `0km` route claim.

## Activity

- Confirm saved workout appears in recent workout list.
- Confirm route badge appears only when route exists.
- Open workout detail.
- Confirm route map appears when route exists.
- Confirm route-missing state stays calm and does not show developer copy.
- Confirm share actions are available from detail.

## Share

- Open image share composer from Activity Detail.
- Swipe carousel: workout, condition, course, club.
- Save image to Photos.
- Test transparent card. Expected: preview checkerboard appears, exported image does not include checkerboard.
- Use More share sheet.
- Use Instagram label. Expected: copy says to choose Instagram from iOS share screen, not direct Story API.
- Confirm Copy Link is hidden.

## Profile

- Open Profile with no workouts.
- Confirm starter identity copy appears.
- Save a workout with distance.
- Reopen Profile.
- Confirm identity phrase, active days, total distance, primary sport, PB, and badge state respond to saved workouts.
- Confirm Profile does not show a recent workout list.

## Club

- Open Club Home.
- Confirm joined/created/recommended sections load.
- Create a local or staging club.
- Join a club.
- Leave a club.
- Open Club Detail.
- Switch ranking metric.
- Confirm motivation layer shows rank change, contribution, next goal, and pulse.
- Confirm challenge remaining action copy is present.
- Restart app and confirm local persistence remains for local-first state.

## Feed

- Open Feed.
- Confirm feed cards keep the established visual language.
- Confirm local share drafts appear as draft/private, not public posts.
- Confirm no recovery guidance leaks into public feed copy.

## Global

- Confirm selected/CTA/progress accents use SOOM purple.
- Confirm major screens do not show developer words: mock, fallback, placeholder, backend, deferred.
- Confirm loading and error states use product-language copy.
- Confirm Floating Coach does not cover core actions in Record, Activity, or Club.
- Confirm app remains usable offline where local-first behavior is expected.
