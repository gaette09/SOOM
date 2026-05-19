# SOOM SwiftData Integration Plan

## A. Purpose

이 문서는 SOOM Check-in persistence를 mock 기반 흐름에서 SwiftData 기반 로컬 저장으로 전환하기 전의 안전 점검과 연결 계획을 정의한다.

SwiftData를 연결하는 이유:

- 앱 재실행 후에도 사용자가 입력한 Check-in 기록을 유지한다.
- Recovery 화면의 최신 컨디션 요약, coach message, insight 개인화를 실제 기록 기반으로 유지한다.
- 향후 주간 컨디션 추세, 수정/삭제, iCloud 또는 서버 동기화로 확장할 로컬 데이터 기반을 만든다.
- SOOM의 Native iOS / SwiftUI 방향에 맞는 앱 내부 데이터 모델을 준비한다.

이 문서는 SwiftData 연결 계획과 rollout 상태를 다룬다. 현재는 Phase 2부터 Phase 5까지 완료되어 앱 전역 `ModelContainer`, Check-in 저장, Recovery latest check-in 읽기가 모두 SwiftData source of truth를 공유한다. `CheckInViewModel`과 `RecoveryViewModel`의 기본 init은 Preview, Unit Test, rollback을 위해 mock store를 유지하고, 실제 앱 진입은 Container를 통해 SwiftData store를 명시 주입한다.

## B. Current State

현재 구현된 상태:

- `CheckInRecord` SwiftData persistence model 구현 완료
- `RecoveryCheckInPersistenceMapper` 구현 완료
- `SwiftDataCheckInStore` 구현 완료
- `SwiftDataCheckInStoreTests`에서 in-memory `ModelContainer` 기반 저장/조회/필터링 테스트 통과
- `RecoveryCheckInStore` / `RecoveryCheckInWritableStore` protocol 유지
- 앱 전역 `ModelContainer`는 `SOOMApp.swift`의 `WindowGroup`에 `.modelContainer(for: CheckInRecord.self)`로 연결 완료
- `CheckInViewContainer`는 production Check-in 저장 흐름에서 `SwiftDataCheckInStore`를 사용한다.
- `RecoveryViewContainer`는 production Recovery latest check-in 읽기 흐름에서 `SwiftDataCheckInStore`를 사용한다.
- `CheckInViewModel`과 `RecoveryViewModel`의 기본 init은 Preview/Test/rollback을 위해 아직 mock store를 유지한다.

현재 구조는 SwiftData store가 앱에 연결된 상태다. SwiftUI의 `@Environment(\.modelContext)`와 `@StateObject` 초기화 타이밍 문제를 피하기 위해 production entry는 `CheckInViewContainer`, `RecoveryViewContainer`, `CheckInHistoryViewContainer`, `CheckInDetailViewContainer`, `CheckInEditViewContainer`를 사용한다.

## C. Recommended Integration Point

### Option 1: `SOOMApp.swift`에서 전역 연결

후보 코드:

```swift
WindowGroup {
    RootTabView()
        .environmentObject(dashboardViewModel)
        .environmentObject(communityViewModel)
}
.modelContainer(for: CheckInRecord.self)
```

장점:

- 앱 전체에서 하나의 SwiftData container를 공유한다.
- Recovery, Check-in, 향후 Profile/Settings에서도 같은 저장소를 사용할 수 있다.
- SOOM의 앱 내부 데이터가 늘어날 때 가장 자연스럽게 확장된다.

단점:

- 앱 진입점이 persistence schema를 알게 된다.
- Preview와 Unit Test에서 별도 in-memory container 주입 정책이 필요하다.
- schema migration 문제가 앱 시작 단계의 리스크가 된다.

권장도: 높음. SOOM v1의 기본 방향으로 가장 적합하다.

### Option 2: `RootTabView` 상위 또는 내부에서 연결

후보:

- `SOOMApp`은 그대로 두고 `RootTabView` 또는 그 상위 wrapper view에 `.modelContainer(for:)` 적용

장점:

- 앱 진입점 변경 폭을 조금 줄일 수 있다.
- 특정 화면 그룹만 SwiftData를 사용할 때는 범위를 좁힐 수 있다.

단점:

- `RootTabView`는 현재 탭 상태, 탭바, navigation composition 책임을 이미 가진다.
- persistence 주입 책임까지 추가되면 RootTabView 책임이 커진다.
- Recovery 외 Feature가 SwiftData를 사용하기 시작하면 다시 앱 루트로 옮길 가능성이 높다.

권장도: 중간. 임시 검증에는 가능하지만 장기 구조로는 `SOOMApp` 연결이 더 명확하다.

### Recommended

SOOM v1에서는 `SOOMApp.swift`의 `WindowGroup` scene에 `.modelContainer(for: CheckInRecord.self)`를 적용하는 방식을 우선 추천한다.

단, 실제 store 교체는 한 번에 하지 않는다. 먼저 앱에 `ModelContainer`만 추가해 빌드/실행 안정성을 확인하고, 이후 `CheckInViewModel` 생성 구조를 정리한 뒤 화면 단위로 SwiftData store를 사용한다.

## D. ViewModel DI Strategy

현재 구조:

- `CheckInViewModel`은 `RecoveryCheckInWritableStore` protocol에 의존한다.
- `RecoveryViewModel`은 `RecoveryCheckInStore` protocol에 의존한다.
- `SwiftDataCheckInStore`는 `ModelContext`가 필요하다.
- `CheckInView`는 기본 init에서 `CheckInViewModel()`을 직접 생성한다.

주의할 점:

- SwiftUI `@Environment(\.modelContext)`는 View의 `init` 안에서 직접 사용할 수 없다.
- `@StateObject`는 한 번 초기화되면 이후 environment 변경에 따라 자동 재생성되지 않는다.
- 따라서 `CheckInView` 기본 init에서 바로 `SwiftDataCheckInStore(modelContext:)`를 만드는 구조는 안전하지 않다.

### Candidate A: View 내부 Factory Wrapper

권장 후보:

```swift
struct CheckInView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        CheckInViewContent(
            viewModel: CheckInViewModel(
                store: SwiftDataCheckInStore(modelContext: modelContext)
            )
        )
    }
}
```

이 방식은 환경 값을 body에서 읽은 뒤 content view에 ViewModel을 주입할 수 있다. 다만 ViewModel 재생성 타이밍을 조심해야 하므로, 실제 구현에서는 `@StateObject`를 가진 factory/helper view를 별도로 두는 편이 좋다.

### Candidate B: `CheckInViewModelFactory`

후보:

- `CheckInViewModelFactory` 또는 `RecoveryDependencyContainer`를 만든다.
- factory가 `ModelContext`를 받아 `CheckInViewModel(store:)`를 생성한다.
- Preview/Test에서는 mock factory를 사용한다.

장점:

- ViewModel 생성 책임이 View에서 줄어든다.
- mock/store 전환이 명확하다.
- 향후 RecoveryViewModel도 같은 store를 공유하기 쉽다.

단점:

- v1 MVP에는 파일이 조금 늘어난다.

### Candidate C: Environment Dependency Container

후보:

- `EnvironmentKey`로 Recovery dependencies를 주입한다.
- `CheckInView`와 `RecoveryView`가 같은 dependency container에서 store를 꺼낸다.

장점:

- 여러 화면에서 같은 store/provider를 안정적으로 공유할 수 있다.
- 장기적으로 앱 규모가 커질 때 좋다.

단점:

- 지금 단계에서는 구조가 다소 무겁다.

### Recommended

Phase 3에서는 작은 factory wrapper부터 시작하는 것을 추천한다.

원칙:

- `CheckInViewModel`과 `RecoveryViewModel`은 계속 protocol에만 의존한다.
- `SwiftDataCheckInStore` 생성은 `ModelContext`를 읽을 수 있는 SwiftUI View 계층 또는 dependency factory에서만 한다.
- mock store는 Preview/Test 전용으로 유지한다.

## E. Risks

### SwiftUI Environment and ViewModel Initialization

`@Environment(\.modelContext)`는 `View.init`에서 사용할 수 없다. 현재 `CheckInView`는 `init()`에서 `CheckInViewModel()`을 바로 만들기 때문에, SwiftData store 교체 시 구조 변경이 필요하다.

### `@StateObject` Lifetime

`@StateObject`는 View 생명주기 동안 한 번만 초기화된다. `ModelContext`를 나중에 주입하거나 바꾸는 구조와 섞이면 예상과 다른 store가 유지될 수 있다.

### Preview Stability

Preview에서 `.modelContainer(for:)` 또는 in-memory container를 제공하지 않으면 `CheckInView`와 `RecoveryView` preview가 깨질 수 있다.

### Test Container Lifetime

SwiftData 테스트에서 `ModelContext`만 보관하고 `ModelContainer`가 해제되면 `insert` 시 런타임 trap이 발생할 수 있다. 테스트와 앱 모두 container 생명주기를 명확히 유지해야 한다.

### Shared Mock and Real Store Mixed State

`CheckInView`만 SwiftData를 쓰고 `RecoveryViewModel`은 mock store를 계속 보면, 저장 후 Recovery 화면에 최신 check-in이 보이지 않는 혼재 상태가 생길 수 있다. 화면 단위 전환 순서를 명확히 해야 한다.

### Main Actor Boundary

`SwiftDataCheckInStore`는 `@MainActor`로 설계되어 있다. ViewModel에서 호출할 때 현재처럼 async store protocol을 유지하면 안전하지만, background actor에서 직접 호출하는 구조는 피한다.

### Migration and Schema Changes

`CheckInRecord`가 production persistence가 된 뒤에는 필드 변경, optional 처리, migration 정책을 더 신중히 다뤄야 한다.

## F. Safe Rollout Plan

### Phase 1: Documentation

- SwiftData integration plan을 문서화한다.
- 앱 연결 전 대상 파일과 리스크를 확인한다.
- 이 단계에서는 production code를 변경하지 않는다.

### Phase 2: Add App-Level ModelContainer Only

- `SOOMApp.swift`의 `WindowGroup`에 `.modelContainer(for: CheckInRecord.self)`를 추가한다.
- `CheckInViewModel` 기본 store는 mock으로 유지한다.
- 앱 실행, Recovery/Check-in 화면 진입, build/test를 확인한다.

상태: 완료.

완료 내용:

- `SOOMApp.swift`에 SwiftData를 import했다.
- `WindowGroup` scene에 `.modelContainer(for: CheckInRecord.self)`를 추가했다.
- `CheckInViewModel`과 `RecoveryViewModel`의 기본 mock store 흐름은 그대로 유지했다.
- `@Environment(\.modelContext)` 사용, factory 구조 변경, SwiftData store 주입은 아직 하지 않았다.

목표:

- SwiftData schema가 앱 시작 시 안전하게 로드되는지 확인
- 기존 UI/UX가 변하지 않는지 확인

### Phase 3: Add CheckInViewModel Factory Structure

- `CheckInView`에서 environment `modelContext`를 안전하게 읽고 ViewModel을 생성할 수 있는 wrapper/factory를 만든다.
- Preview는 in-memory container 또는 mock ViewModel을 유지한다.
- 아직 RecoveryViewModel은 mock latest check-in store를 유지할 수 있다.

상태: 완료.

완료 내용:

- `CheckInViewModelFactory`를 추가해 `CheckInViewModel` 생성 책임을 분리했다.
- 현재 factory 기본 store는 `MockRecoveryCheckInStore.shared`를 사용한다.
- `CheckInView`는 factory 기반 기본 init과 외부 ViewModel 주입 init을 모두 지원한다.
- Preview는 mock 기반 factory를 사용한다.
- 실제 `@Environment(\.modelContext)` 사용과 `SwiftDataCheckInStore` 주입은 아직 하지 않았다.
- `RecoveryViewModel`의 latest check-in store는 mock 흐름을 유지한다.

목표:

- `@Environment`와 `@StateObject` 초기화 타이밍 문제를 피한다.
- CheckInView만 작은 범위로 SwiftData save flow를 검증한다.

### Phase 4: Use SwiftData Store in CheckInView

- `CheckInViewModel` 기본값은 그대로 두되, production `CheckInView` entry에서 `SwiftDataCheckInStore`를 명시 주입한다.
- 저장 후 앱 재실행 시 SwiftData에 기록이 유지되는지 확인한다.
- mock store는 Preview/Test에서 계속 사용한다.

상태: 완료.

완료 내용:

- `CheckInViewContainer`를 추가했다.
- `CheckInViewContainer`는 `@Environment(\.modelContext)`를 읽고 `SwiftDataCheckInStore(modelContext:)` 기반 `CheckInViewModel`을 만든다.
- `RecoveryView`의 “오늘 컨디션 기록하기” 진입부는 `CheckInView()` 대신 `CheckInViewContainer()`를 사용한다.
- `CheckInView()` 기본 init과 Preview는 계속 mock 기반 factory를 사용한다.
- `RecoveryViewModel`의 latest check-in store는 아직 `MockRecoveryCheckInStore.shared` 상태다.
- 따라서 Phase 4에서는 저장은 SwiftData로 되지만, Recovery 화면의 최신 check-in 표시/읽기 흐름은 Phase 5 전환 전까지 mock과 분리되어 있을 수 있다.

목표:

- Check-in 저장만 SwiftData로 전환
- rollback이 쉬운 작은 변경 유지

### Phase 5: Use SwiftData Store for RecoveryViewModel Latest Check-in

- `RecoveryViewModel`의 `checkInStore`도 같은 `SwiftDataCheckInStore`를 보게 한다.
- Check-in 저장 후 Recovery 화면의 `CheckInSummaryCard`, coach message, insights 개인화가 앱 재실행 후에도 유지되는지 확인한다.

상태: 완료.

완료 내용:

- `RecoveryViewContainer`를 추가했다.
- `RecoveryViewContainer`는 `@Environment(\.modelContext)`를 읽고 `SwiftDataCheckInStore(modelContext:)`를 `RecoveryViewModel`의 `checkInStore`로 주입한다.
- Home의 회복 진입부는 `RecoveryView()` 대신 `RecoveryViewContainer()`를 사용한다.
- `CheckInViewContainer` 저장 흐름과 `RecoveryViewContainer` 읽기 흐름이 같은 앱 전역 SwiftData `ModelContainer`를 source of truth로 공유한다.
- `RecoveryView()` 기본 init과 Preview/Test는 rollback과 독립 테스트를 위해 mock 기반 기본값을 유지한다.
- check-in은 latest summary 표시, coach message 개인화, insights 개인화에만 사용하며 score/status/recommendation에는 반영하지 않는다.

목표:

- CheckInView와 RecoveryView가 같은 source of truth를 사용한다.
- score/status/recommendation은 기존 activity 기반 정책을 유지한다.

### Phase 6: Reduce Mock Store to Preview/Test Use

- `MockRecoveryCheckInStore.shared`는 Preview/Test 전용으로 축소한다.
- production code에서 mock 기본값이 남아 있더라도 명시 주입 구조가 우선되도록 정리한다.
- 삭제/수정 기능과 migration test를 별도 작업으로 추가한다.

상태: 진행 중.

완료 내용:

- Check-in 저장, Recovery latest check-in 읽기, History, Detail, Edit entry는 Container를 통해 SwiftData store를 사용한다.
- `MockRecoveryCheckInStore.shared`는 기본 init에 남아 있지만 Preview/Test/rollback 목적임을 코드 주석과 문서에 명시했다.
- Detail 삭제 책임은 `CheckInDetailViewModel`로 이동했다.
- History는 수정 callback을 받아 row를 최신 값으로 교체할 수 있다.

## G. Rollback Plan

문제가 생기면 다음 순서로 되돌린다.

1. `CheckInView` production entry에서 `SwiftDataCheckInStore` 주입을 제거하고 `CheckInViewModel()` 기본 mock 흐름으로 되돌린다.
2. `RecoveryViewModel`의 check-in store 주입을 mock으로 되돌린다.
3. 앱 실행 문제가 있으면 `SOOMApp.swift`의 `.modelContainer(for: CheckInRecord.self)`만 제거한다.
4. `CheckInRecord`, mapper, `SwiftDataCheckInStore`, tests는 남겨두고 연결만 끊는다.

원칙:

- SwiftData 연결은 작은 PR/커밋 단위로 진행한다.
- 각 단계마다 `xcodebuild test`와 `xcodebuild build`를 확인한다.
- Recovery score/status/recommendation 정책은 SwiftData 연결과 분리한다.

## Reviewed File Notes

### `SOOMApp.swift`

- 현재 `DashboardViewModel`, `CommunityViewModel`을 앱 루트에서 생성하고 environment object로 주입한다.
- 전역 `.modelContainer(for: CheckInRecord.self)`가 연결되어 있다.
- Check-in persistence의 앱 전역 source of truth를 제공한다.

### `RootTabView.swift`

- 탭 구성, 탭바 표시 상태, Light Mode only 정책, navigation stack 책임을 가진다.
- persistence container 주입까지 맡기면 책임이 커질 수 있으므로 장기적으로는 `SOOMApp.swift` 연결을 선호한다.
- 이 단계에서는 변경하지 않는다.

### `CheckInView.swift`

- 현재 기본 init에서 mock-backed `CheckInViewModel`을 만든다.
- SwiftData 연결 시 `@Environment(\.modelContext)`를 init에서 읽을 수 없으므로 factory/wrapper 구조가 필요하다.
- production entry는 `RecoveryView`의 `checkInEntryCard`에서 `CheckInViewContainer`를 사용한다.

### `CheckInViewModel.swift`

- 이미 `RecoveryCheckInWritableStore` protocol에 의존한다.
- SwiftData store로 교체 가능한 형태지만, 기본 store는 mock으로 유지해야 rollback이 쉽다.

### `RecoveryView.swift`

- `CheckInViewContainer`, `CheckInHistoryViewContainer`로 진입한다.
- production 저장/조회 흐름은 SwiftData store를 사용한다.

### `RecoveryViewModel.swift`

- `RecoveryCheckInStore` protocol에 의존하고 latest check-in fetch 실패를 Recovery 전체 실패로 처리하지 않는다.
- SwiftData store 연결에 적합한 구조다.
- production `RecoveryViewContainer`에서 `SwiftDataCheckInStore`를 주입받아 CheckInView와 같은 SwiftData source of truth를 본다.
