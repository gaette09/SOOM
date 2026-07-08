# SOOM Record Active HUD Compact/Expand v1

## Files Changed

- `SOOM/Features/Activity/RecordView.swift`
- `SOOM/Features/Activity/RecordLaunchPlan.swift`
- `SOOMTests/RecordWorkoutSessionTests.swift`
- `docs/reports/soom-record-active-hud-compact-expand-v1.md`

## Compact HUD Behavior

- Active Record sessions continue to default to compact mode through `RecordActiveHUDMode.defaultMode`.
- The active overlay is now split into two separate visual layers:
  - compact HUD card
  - action control bar
- Compact HUD sits above the pause/end/cancel controls instead of sharing one large card with them.
- Compact HUD shows elapsed time centered, then the primary live metric:
  - cycling: current speed
  - walking: current speed
  - running: current pace
- Compact typography was increased for easier in-motion reading.
- Expand button remains at the top-right of the compact HUD.

## Expanded HUD Behavior

- Tapping the expand button switches to expanded HUD mode.
- Expanded HUD keeps the existing sport/status header, elapsed time, primary metric, and sport-specific metric grid.
- Collapse button remains at the top-right and returns to compact mode.
- Finished-session summary still uses the full HUD style so save/share flows remain available.

## Sport-Specific Primary Metric Mapping

Existing `RecordActiveHUDLayout` mapping is preserved:

- Cycling: `현재 속도`, `km/h`
- Walking: `현재 속도`, `km/h`
- Running: `현재 페이스`, `/km`

## Layering and Depth Changes

- Compact HUD z-index was raised above right-side map controls.
- Expanded HUD remains the top active layer.
- Compact HUD and action controls now have separate surfaces and shadows, reducing visual crowding near the bottom map/control area.
- Heading follow, navigation cone, and map behavior were not changed.

## Intentionally Not Changed

- Save flow and workout lifecycle.
- Activity Detail behavior.
- Share card behavior.
- Mapbox style URI.
- Route recommendation behavior remains hidden from the right-edge controls.
- TestFlight/build number.

## Verification Results

- Passed: `xcodebuild build -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'generic/platform=iOS Simulator'`
- Passed: focused Record `build-for-testing`
  - `xcodebuild build-for-testing -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SOOMTests/RecordWorkoutSessionTests`
- Blocked by simulator infrastructure: focused test execution
  - `xcodebuild test -quiet -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SOOMTests/RecordWorkoutSessionTests`
  - Result: CoreSimulator failed to clone iPhone 17 and left the device stuck in creation state before tests ran. This is not treated as an app test failure.
- Passed: `git diff --check`

Xcode also emitted physical-device discovery warnings because a connected device is passcode protected. The generic simulator build still completed successfully.

## Device QA Checklist

- Start a Record session for cycling, running, and walking.
- Confirm active session opens in compact HUD mode.
- Confirm compact HUD sits above pause/end/cancel controls.
- Confirm elapsed time is centered and readable.
- Confirm cycling/walking show current speed.
- Confirm running shows current pace.
- Tap expand and confirm the full sport-specific metric grid appears.
- Tap collapse and confirm compact HUD returns.
- Confirm HUD does not visually collide with map controls.
- Confirm heading follow/navigation cone behavior is unchanged.
- Confirm route recommendation remains hidden.
- Pause, resume, finish, cancel, and save flows still behave as before.
