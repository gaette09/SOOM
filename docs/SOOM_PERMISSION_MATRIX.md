# SOOM Permission Matrix

Purpose: define expected app behavior for permission states during TestFlight QA.

## Location

Granted:

- Record can show current location.
- Record can recenter map.
- Record can capture route coordinates and distance while the app is active.
- Weather can fetch from current coordinate when network/API key are available.

Denied:

- Record must not block workout start.
- Workout can save as time-only.
- Weather remains in product-language preparation state.
- Route UI should not claim a route was captured.

Restricted:

- Treat as denied.
- Do not repeatedly prompt.
- Keep local-first time-only save available.

Not Determined:

- Do not request on Record entry.
- Request only when user taps current location or another explicit location action.

## HealthKit

Granted:

- HealthKit import/read flows can use available workout data.
- HealthKit write remains deferred.

Denied:

- App remains usable with local-first workout records.
- Record save does not request HealthKit write permission.
- Profile and Activity use local UnifiedWorkoutStore data.

Restricted:

- Treat as denied.
- Do not show blocking copy.

Not Determined:

- Ask only from an explicit HealthKit connection/import action.

## Notifications

Granted:

- Future reminder/coaching notifications may be enabled.
- No required launch dependency in current TestFlight pass.

Denied:

- App remains fully usable.
- Do not show blocking states.

Restricted:

- Treat as denied.

Not Determined:

- Do not request automatically during core flows.

## Photos

Granted:

- Share image save can write to Photos when the platform flow allows it.

Denied:

- Share can still use the iOS share sheet / More action.
- Product copy should guide the user without claiming failure of the whole share flow.

Restricted:

- Treat as denied.

Not Determined:

- Ask only when user chooses Save Image or a platform path requiring Photos.

## Permission QA Rule

No permission prompt should appear on first app launch solely because a tab was opened. Prompts should be user-initiated, scoped, and recoverable.
