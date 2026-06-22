# SOOM 0009 Scaffold Lock Plan

Date: 2026-06-22

Task:

- `tasks/soom/0009-record-detail-content-lock.md`

Inputs inspected:

- `docs/specs/STRAVA_ACTIVITY_DETAIL_LAYOUT_SPEC.md`
- `docs/reports/soom-0009-production-routing-plan.md`
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`
- `SOOM/Features/Activity/WorkoutSheetState.swift`
- `SOOM/Features/Activity/WorkoutBottomSheet.swift`
- `SOOM/Features/Activity/WorkoutSheetHeader.swift`
- `SOOM/DesignSystem/SoomSpacing.swift`

## 1. Current Scaffold States

Current production route-backed Record Detail path:

```text
WorkoutDetailView
  -> WorkoutMapSheetScaffold
  -> WorkoutBottomSheet
  -> WorkoutDetailContent(presentationStyle: .mapSheet)
```

Current state model:

| State | Source | Current behavior |
| --- | --- | --- |
| `minimized` | `WorkoutSheetPosition` | Small sheet height using `minimizedRatio = 0.18`, with map scale `1.36`. |
| `standard` | `WorkoutSheetPosition` | Initial sheet state. Uses `standardRatio = 0.56`, min `468`, max `600`, map scale `3.00`. |
| `expanded` | `WorkoutSheetPosition` | Full-height sheet using `expandedHeight = proxy.size.height + safeAreaTop + expandedTopOverflow`; map scale `2.36`. |

Current default:

```swift
@State private var sheetPosition: WorkoutSheetPosition = .standard
```

Current drag behavior:

- Non-expanded sheet can drag to nearest `minimized`, `standard`, or `expanded`.
- Expanded sheet can begin collapsing when internal scroll offset is at the top and the user drags downward.
- `WorkoutSheetPosition.nearest(...)` includes all three states.

Current header behavior:

- Preview/standard state shows `WorkoutSheetHandleButton`.
- Expanded state shows `WorkoutSheetHeader` inside `WorkoutBottomSheet`.
- Map controls fade out in expanded state.
- There is no fixed top nav outside the sheet equivalent to the frame-lock prototype.

## 2. Differences From Frame Lock Spec

| Area | Frame Lock spec | Current scaffold |
| --- | --- | --- |
| State count | Two states: preview and expanded. | Three states: minimized, standard, expanded. |
| Initial state | Preview sheet top at `screenHeight * 0.64`. | Initial state is `.standard`, computed from sheet height ratio/min/max. |
| Coordinate model | Sheet offset is measured from absolute screen top. | Sheet is height-based and bottom-aligned with `sheetYOffset`. |
| Map visibility | Preview map visible ratio is exactly `0.64` of screen height. | Standard state visible map area is indirect and varies through height clamps. |
| Top nav | Fixed top nav is outside sheet and remains spatially stable. | Expanded title/actions live inside the sheet header. |
| Preview controls | Header floats over map. | `WorkoutMapControls` floats over map, but disappears when expanded. |
| Expanded top | Sheet starts at absolute Y = `0`; no map visible behind status/nav. | Expanded uses height overflow plus `expandedYOffset = -36`; background cover is separate opacity layer. |
| Drag ownership | Handle owns preview-to-expanded transition; no overscroll collapse in first pass. | Expanded sheet can collapse via scroll-top downward drag. |
| Scroll ownership | Internal `ScrollView` enabled only in expanded. | Already mostly true, but drag gesture remains simultaneous on entire sheet. |
| Map camera | Keep map camera stable until sheet motion is solved. | Map camera animates when `sheetPosition` changes. |
| Handle constants | Width `40`, height `4`. | Width `52`, height `6`. |
| Corner radius | Preview `14`, expanded `0`. | Uses design radius from `SOOMRadius.detailSheetTop`; expanded radius reaches `0` only under threshold. |
| Content horizontal padding | `32`. | Current sheet content uses `SOOMLayout.screenPadding` (`20`). |

## 3. Minimum Safe Behavior Changes

Recommended next implementation should be a scaffold-only behavior lock, not a full content redesign.

Minimum safe changes:

1. Collapse the production map sheet to two effective states:
   - preview
   - expanded

2. Keep route-backed production routing unchanged:
   - `WorkoutDetailView` still uses `WorkoutMapSheetScaffold` when `detailMapRoute != nil`.
   - standalone fallback remains unchanged.

3. Change the initial state from `.standard` to a frame-lock preview state.

4. Remove `minimized` from snap candidates for route detail.

5. Disable overscroll-to-collapse in the first scaffold lock:
   - preview-to-expanded should be handle/sheet-drag owned.
   - expanded content should scroll without also owning collapse.

6. Stop animating the map camera on sheet state change for the lock pass.

7. Keep existing header implementation for this next commit unless changing it is required to compile.

8. Do not prune `WorkoutDetailContent` yet.

9. Do not change user-facing copy yet.

10. Do not introduce a new production top nav yet.

Rationale:

- The production routing commit already made route-backed workouts enter the scaffold.
- The next safest step is to make the scaffold behave closer to the frame-lock state model.
- Fixed top nav and content padding are larger visual changes and should be separate commits.

## 4. Exact Code Changes Needed

### A. `SOOM/DesignSystem/SoomSpacing.swift`

Add frame-lock constants under `SOOMLayout.DetailSheet`:

```swift
static let previewSheetTopRatio: CGFloat = 0.64
static let expandedSheetTop: CGFloat = 0
static let frameLockHandleWidth: CGFloat = 40
static let frameLockHandleHeight: CGFloat = 4
```

Optional for later, not required in the first scaffold lock:

```swift
static let navHeight: CGFloat = 56
static let navTouchTargetHeight: CGFloat = 44
static let expandedContentTopPaddingBelowNav: CGFloat = 36
static let frameLockContentHorizontalPadding: CGFloat = 32
```

### B. `SOOM/Features/Activity/WorkoutSheetState.swift`

Replace the effective state model with preview/expanded, or make `.standard` behave as preview and prevent `.minimized` selection.

Minimum low-risk option:

```swift
enum WorkoutSheetPosition: CaseIterable {
    case standard
    case expanded
}
```

Then update `nearest(...)` to compare only:

```swift
let candidates: [(WorkoutSheetPosition, CGFloat)] = [
    (.standard, standard),
    (.expanded, expanded)
]
```

Change `standardHeight` to derive from preview top:

```swift
let screenHeight = UIScreen.main.bounds.height
let previewSheetTop = screenHeight * SOOMLayout.DetailSheet.previewSheetTopRatio
standardHeight = max(screenHeight - previewSheetTop, 1)
```

Keep `expandedHeight` compiling for the current bottom-aligned scaffold:

```swift
expandedHeight = max(proxy.size.height + proxy.safeAreaInsets.top + SOOMLayout.DetailSheet.expandedTopOverflow, standardHeight)
```

This is not the final absolute top-offset model, but it makes the visible preview area closer to the `0.64` spec without rewriting `WorkoutBottomSheet`.

### C. `SOOM/Features/Activity/WorkoutSheetHeader.swift`

Update handle toggle logic because `.minimized` would no longer exist:

```swift
sheetPosition = sheetPosition == .standard ? .expanded : .standard
```

If handle sizing is included in this commit, update:

```swift
.frame(
    width: SOOMLayout.DetailSheet.frameLockHandleWidth,
    height: SOOMLayout.DetailSheet.frameLockHandleHeight
)
```

### D. `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`

Keep:

```swift
@State private var sheetPosition: WorkoutSheetPosition = .standard
```

Change expanded drag ownership:

```swift
private func canMoveSheet(_ value: DragGesture.Value, metrics: WorkoutSheetMetrics) -> Bool {
    if metrics.isExpanded {
        return false
    }

    return true
}
```

Change snap projection to use only standard/expanded candidates after `WorkoutSheetPosition.nearest(...)` is narrowed.

Remove or defer map camera animation on sheet position change:

```swift
// Remove for frame-lock phase, or guard it behind a future flag.
```

Keep current `WorkoutBottomSheet`, `WorkoutSheetHeader`, and `WorkoutMapControls` structure for the first behavior lock.

### E. `SOOM/Features/Activity/WorkoutBottomSheet.swift`

No minimum change required for the next commit.

Later frame-lock work should move from height/bottom alignment to absolute top-offset anchoring, but that is not the minimum safe behavior change.

## 5. Verification Steps

Required build:

```sh
xcodebuild -project SOOM.xcodeproj -scheme SOOM -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Manual simulator checks:

1. Launch a route-backed workout detail.
2. Confirm initial visible map area is closer to the `0.64` target and the sheet starts lower than the old standard state if the old state was too high.
3. Confirm there is no minimized snap state.
4. Drag preview sheet upward and confirm it expands.
5. In expanded state, scroll content and confirm normal internal scrolling.
6. Confirm dragging inside expanded scroll content does not collapse the sheet through overscroll.
7. Use the visible collapse control and confirm the sheet returns to preview/standard.
8. Confirm no duplicate inline hero map appears in sheet content.
9. Open a non-route workout detail and confirm standalone fallback still renders.

Recommended git checks:

```sh
git diff --stat
git status --short
```

Expected changed files for the next scaffold lock commit:

- `SOOM/DesignSystem/SoomSpacing.swift`
- `SOOM/Features/Activity/WorkoutSheetState.swift`
- `SOOM/Features/Activity/WorkoutSheetHeader.swift`
- `SOOM/Features/Activity/WorkoutMapSheetScaffold.swift`

Optional if needed:

- `SOOM/Features/Activity/WorkoutBottomSheet.swift`

## 6. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Removing `.minimized` could affect non-Record uses of `WorkoutMapSheetScaffold`. | Feed detail or other map sheet flows may lose a state they relied on. | Search call sites before implementation; if needed, add a scaffold configuration instead of changing global behavior. |
| Preview height derived from `UIScreen.main.bounds.height` may mismatch split-screen or unusual simulator contexts. | Sheet anchor may be wrong outside standard portrait usage. | This matches the spec first pass; verify on iPhone 17 Pro first before broadening. |
| Keeping bottom-aligned sheet architecture means the scaffold is not fully frame-lock compliant yet. | Visual behavior may still differ from absolute top-offset spec. | Treat this as behavior lock phase 1; plan a later absolute-offset refactor. |
| Disabling overscroll collapse may make collapse depend only on the header control. | Users may need an explicit control to collapse. | Accept for frame-lock phase because the spec explicitly avoids overscroll collapse first pass. |
| Removing map camera animation may expose route framing issues in preview/expanded states. | Route could look less optimized after expansion. | Keep route stable for motion lock, then tune map framing after sheet behavior is stable. |
| Existing expanded header is still inside the sheet. | Expanded state will not fully match fixed top nav spec. | Defer fixed top nav extraction to a separate focused commit. |

## Recommended Next Commit

Implement only scaffold behavior lock phase 1:

- two effective states,
- preview ratio lock,
- no minimized snap,
- no overscroll collapse,
- no map camera animation on sheet state change.

Do not change production routing, content pruning, copy, or top-nav architecture in the same commit.

