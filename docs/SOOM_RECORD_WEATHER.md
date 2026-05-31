# SOOM Record Weather Service

Record weather is an optional enhancement for the fullscreen map launch experience.

## Principles

- Record never requests location permission on entry.
- Live weather is attempted only after the user taps the current-location button and SOOM has an authorized coordinate.
- Missing location, missing API key, network failure, or parse failure falls back to the calm mock weather snapshot.
- Weather never blocks READY or local-first workout start.
- API keys are injected through local/CI secrets and are never committed.

## Local Configuration

Supported key names:

- `OPENWEATHER_API_KEY`
- `WEATHER_API_KEY`

Preferred local options:

- Xcode scheme environment variable for simulator/device debugging.
- Local `.xcconfig` excluded from git.
- CI/App Store Connect secret injection for release validation.

Do not paste a real weather API key into Swift source, `Info.plist`, docs, or test fixtures.

## UI Behavior

The weather pill shows temperature and condition first, with wind folded in when available:

- `26° · 맑음`
- `26° · 맑음 · 바람 약함`

The recommendation pill can include a short weather lead:

- `맑고 바람이 약해요 · Z2 40분`
- `비가 오면 짧게, 미끄럼만 조심해요 · 조깅 25분`
- `맑지만 바람이 강해요 · Z2 40분`

## Deferred

- Provider selection UI.
- Forecast instead of current conditions.
- Weather-aware route recommendation backend.
- Weather history stored with completed workouts.
