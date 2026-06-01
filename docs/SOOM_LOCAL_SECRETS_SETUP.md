# SOOM Local Secrets Setup

SOOM uses local-only secrets for development builds. Real values must stay out of git.

## Recommended Setup

1. Copy the example file:

```sh
cp SOOM/Config/LocalSecrets.example.xcconfig SOOM/Config/LocalSecrets.xcconfig
```

2. Replace the placeholder values in `SOOM/Config/LocalSecrets.xcconfig`:

```xcconfig
MBX_ACCESS_TOKEN=pk.your_mapbox_token_here
OPENWEATHER_API_KEY=your_openweather_key_here
```

3. Debug builds are wired through `SOOM/Config/Debug.xcconfig`, which optional-includes `LocalSecrets.xcconfig`. Use the local file only on your machine:

```sh
xcodebuild -project SOOM.xcodeproj -scheme SOOM -xcconfig SOOM/Config/LocalSecrets.xcconfig -showBuildSettings
```

For Xcode UI runs, the SOOM target's Debug configuration already reads `Debug.xcconfig`. Do not paste real values into `Info.plist`, source files, docs, or committed project settings.

## Runtime Paths

- Mapbox reads `MBXAccessToken` from `Info.plist`, backed by `$(MBX_ACCESS_TOKEN)`.
- Record weather reads `OPENWEATHER_API_KEY` or `WEATHER_API_KEY` from process environment or `Info.plist`.
- Missing, unresolved, placeholder, or failed network values must keep the fallback map/weather behavior.

## Verification

Check that local secrets are ignored:

```sh
git check-ignore -v SOOM/Config/LocalSecrets.xcconfig
git status --short
```

Check build setting injection. Prefer a sanitized check so token values are not printed:

```sh
xcodebuild -project SOOM.xcodeproj -scheme SOOM -configuration Debug -showBuildSettings | awk 'index($0, "MBX_ACCESS_TOKEN =") {value=$0; sub(/^.*= /, "", value); configured=(value != "" && value !~ /^\$\(/ && value !~ /your_mapbox_token_here/); print "MBX_ACCESS_TOKEN_CONFIGURED=" configured} index($0, "OPENWEATHER_API_KEY =") {value=$0; sub(/^.*= /, "", value); configured=(value != "" && value !~ /^\$\(/ && value !~ /your_openweather_key_here/); print "OPENWEATHER_API_KEY_CONFIGURED=" configured}'
```

Manual Record QA:

- Open Record.
- Expected with `MBX_ACCESS_TOKEN`: Mapbox base map appears instead of mock fallback.
- Tap the location button.
- Approve location when prompted.
- Expected with `OPENWEATHER_API_KEY`: weather pill updates from fallback after a coordinate is available.

Never commit `SOOM/Config/LocalSecrets.xcconfig`.
