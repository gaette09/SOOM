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

## Detail Sheet

The Record weather sheet is fixed height and internal-scroll only. It should not expose multiple detents or allow drag expansion.

The detail layout includes:

- Current location label, current weather icon, temperature, condition, feels-like, and wind.
- Air quality cards for PM10 and PM2.5.
- Hourly forecast rows.
- Daily forecast rows.
- A short guide card for air quality, rain/snow/wind, or heat.

Air quality uses a simple readable color system:

- `좋음`: blue
- `보통`: green
- `나쁨`: orange
- `매우 나쁨`: red

## Provider Foundation

Live detail weather uses OpenWeather foundations:

- One Call API 3.0 for current, hourly, and daily weather.
- Air Pollution API for AQI, PM10, and PM2.5.

If One Call fails, SOOM keeps the fallback detail snapshot. If Air Pollution fails but weather succeeds, SOOM keeps weather detail and uses fallback air-quality values.

## Deferred

- Provider selection UI.
- Weather-aware route recommendation backend.
- Weather history stored with completed workouts.
