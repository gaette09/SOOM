# SOOM UX Foundation Architecture Plan

## 목적과 범위

이 문서는 기존 SOOM iOS 프로젝트를 유지한 채 Feed 중심 UX 확장을 준비하기 위한 경계와 이행 순서를 정의한다. 이번 단계는 **계획 문서만** 다룬다. Production UI, 새 Navigation 구조, Feature 삭제, Android 작업은 포함하지 않는다.

현재 루트 탭은 `Feed → Activity → Record → Club → Profile`이며, Record는 중앙 탭을 눌러 `fullScreenCover`로 연다. 이 진입 방식과 기존 Feature는 유지한다.

## 현재 상태 요약

| 영역 | 현재 관찰 | 정리 필요성 |
| --- | --- | --- |
| App root | `RootTabView.swift`가 탭 선택, tab bar 표시 상태, Record presentation/복귀 정책, floating recovery coach, 그리고 private `ActivityView`까지 소유한다. | 루트 조립 책임과 Activity 화면 책임을 분리한다. |
| Activity | `DashboardViewModel(harness: MockWorkoutHarness())`의 `Workout`과 SwiftData의 `UnifiedWorkout`을 한 화면에서 결합한다. | 화면에 전달되는 production read model을 하나로 정한다. |
| Feed | 기본 `FeedView()`가 `FeedMockData` 및 `.mockOnly` data source를 사용하며, `FeedDataSource`에는 remote + mock fallback + local share draft 병합이 있다. | mock fallback을 앱 기본 production 흐름과 분리한다. |
| Recovery | `RecoveryActivitySource.defaultSource`가 `.mock`이고 `RecoveryViewContainer`도 이를 사용한다. `HomeView`에는 Recovery 진입점이 있으나 root content는 아니다. | root tab을 늘리지 않고 Feed 맥락 안에 노출 위치를 확정한다. |
| Record | `RecordView`의 시작 계획은 `RecordLaunchPlan.mockToday`이나 저장은 `SwiftDataUnifiedWorkoutStore`를 사용한다. | demo launch plan과 실제 기록 저장 결과의 역할을 분리한다. |

## 1. RootTabView 책임 분리 계획

### 목표 구조

`RootTabView`는 앱 shell로 축소한다. 다음만 소유한다.

- 선택된 `SOOMTab` 상태와 `SOOMBottomTabBar` 연결
- `SOOMTabBarVisibility`, bottom overlay inset, 공통 light appearance 적용
- 중앙 Record action의 `fullScreenCover` presentation
- Record 완료/취소 후의 기존 복귀 정책: 저장 완료는 Activity, 공유 완료/취소는 Feed

다음은 root에서 제거해 각 Feature 또는 전용 조립 지점으로 옮긴다.

| 현재 RootTabView 책임 | 목표 소유자 | 이행 방식 |
| --- | --- | --- |
| private `ActivityView` 및 Activity 전용 보조 타입 | `Features/Activity` | `ActivityView.swift`와 필요한 Activity-local type으로 이동한다. 외부 API는 `ActivityView()` 하나로 제한한다. |
| Feed/Activity/Club/Profile별 `NavigationStack` 조립 | tab content factory 또는 각 Feature root wrapper | 탭별 독립 stack을 유지하되, root 본문은 탭-Feature 매핑만 선언한다. 새 router/path는 만들지 않는다. |
| Floating Recovery Coach와 mock summary | Recovery presentation component | 이번 단계에서는 비활성 상태를 유지한다. 재노출 시에는 Recovery의 production-facing summary provider만 주입하도록 별도 조립 지점을 만든다. |
| Record completion의 탭 전환 판단 | `RecordPresentationCoordinator`(root-local state object 또는 작은 coordinator) | closure 의미를 `cancel`, `saved`, `shared` 결과로 명확히 하고, 현재 화면 동작을 변경하지 않는다. |

### 이행 순서

1. `RootTabView`의 Activity 선언과 Activity-local helper를 `Features/Activity`로 기계적으로 이동한다. 동작과 접근성 문구는 변경하지 않는다.
2. tab content를 Feature root view 단위로 조립하도록 정돈하고, 모든 탭의 기존 `NavigationStack` 및 destination을 유지한다.
3. Record closure 세 개를 결과 기반 coordinator API로 정리한다. `fullScreenCover`와 현재 복귀 탭 규칙은 그대로 둔다.
4. Floating coach는 계속 feature flag off 상태로 둔다. mock summary를 production root에서 다시 활성화하지 않는다.
5. 각 이동 후 빌드 및 관련 테스트를 실행한다. 이 단계에서 UI 레이아웃 변경은 허용하지 않는다.

## 2. Feature boundary 정의

| Feature | 소유 책임 | 허용 의존성 | 금지/비소유 책임 |
| --- | --- | --- | --- |
| Feed | 피드 목록/상세, 공유 초안 표시, Feed post read model, Feed repository contract | Feed repository, share-draft store, 운동 상세로의 기존 destination에 필요한 read-only adapter | Activity의 SwiftData query를 직접 수행하거나 `MockWorkoutHarness`를 직접 참조하지 않는다. |
| Activity | 개인 운동 라이브러리, 운동 목록/상세 진입, 캘린더·통계 read model | `UnifiedWorkoutStore`, activity query/use-case, workout detail adapter | root tab state, Feed post 생성, mock dashboard 목록을 production 목록과 합치지 않는다. |
| Record | 기록 시작/진행/저장, 위치·날씨·지도 session, 저장 완료 결과 | `RecordWorkoutSessionStarter`, `RecordWorkoutSaveFlow`, `UnifiedWorkoutStore`, location/weather abstractions | tab 선택/복귀 정책, Feed 목록 refresh 정책을 소유하지 않는다. 결과만 상위 조립자에 전달한다. |
| Club | 클럽 directory, 가입/생성/랭킹/챌린지 | `ClubService`, auth session의 현재 사용자 식별자 | Feed/Activity 데이터의 소유 또는 Recovery root 노출을 맡지 않는다. |
| Profile | 계정/설정, 개인 요약과 연결 관리 | auth, settings, personal workout aggregation, HealthKit settings | Activity 라이브러리의 canonical query나 Feed repository를 소유하지 않는다. |
| Recovery (cross-cutting) | readiness/check-in/timeline, recovery summary와 상세 | Recovery provider, check-in/snapshot store, UnifiedWorkout-derived adapter | 독립 root tab을 만들거나 `RootTabView`에 mock data를 제공하지 않는다. |

공유 모델은 Feature 간에 직접 UI 타입을 전달하지 않는다. `UnifiedWorkout`은 개인 운동 저장의 canonical domain model로 유지하고, Feed는 공유에 필요한 `FeedShareDraft`/`FeedItem`으로 변환해 소유한다. Activity가 legacy `Workout` 상세 화면을 계속 열어야 하는 동안에는 Feature 경계의 adapter에서만 변환한다.

## 3. Activity data source 정책

### Canonical production source

Activity 화면의 production 목록, 통계, 캘린더, 최근 운동은 `UnifiedWorkoutStore`를 통해 읽은 `UnifiedWorkout`만 사용한다. 현재 저장 구현인 `SwiftDataUnifiedWorkoutStore`가 앱 조립 단계의 기본 구현이다. HealthKit/FIT/GPX import와 Record 저장은 이 store로 수렴한 뒤 Activity에 반영한다.

### Read-model policy

1. Activity Feature 안에 `ActivityWorkoutQuerying` 같은 read contract를 둔다. 화면은 `ActivityLibraryEntry`를 직접 조합하지 않고 query 결과의 Activity 전용 read model만 렌더링한다.
2. `UnifiedWorkout → Activity read model` 변환은 Activity Feature에 둔다. SwiftData record, `DashboardViewModel`, `WorkoutHarness`를 view가 동시에 알지 않도록 한다.
3. production에서는 최근 180일 같은 조회 범위와 정렬 기준을 query/use-case에 명시하고, 빈 상태는 빈 production 결과만으로 결정한다.
4. legacy `WorkoutDetailView`가 필요하면 `UnifiedWorkout`에서 detail adapter를 통해 만들고, adapter 제거 전까지 `DashboardViewModel.workouts`를 comparison input의 production 대체값으로 사용하지 않는다.

### Temporary compatibility rule

`DashboardViewModel`과 `MockWorkoutHarness`는 Preview, UI harness, 또는 명시적 test injection에만 남긴다. Activity production root가 이를 environment object로 읽거나 SwiftData 결과와 merge하는 것을 금지한다. migration 동안 dashboard 기반 demo 화면이 필요하면 `ActivityView`가 아닌 별도 preview/harness entry point에서만 구성한다.

## 4. Mock harness와 production model 분리 계획

### 분류 규칙

| 분류 | 위치와 사용 | 앱 기본 조립에서의 규칙 |
| --- | --- | --- |
| Production domain/persistence | `UnifiedWorkout`, `UnifiedWorkoutStore`, SwiftData record/mapper, HealthKit/import pipeline, remote repository | app root 또는 Feature container가 명시적으로 주입한다. |
| Production read model | Activity/Feed/Recovery가 각자의 화면을 위해 만든 immutable display model | 다른 Feature에는 repository/use-case 결과 또는 명시적 adapter만 전달한다. |
| Mock fixture/harness | `MockWorkoutHarness`, `FeedMockData`, `RecoveryMockData`, preview-only store/provider | `Preview`, test target, 또는 명시적 debug/harness initializer에서만 사용한다. |
| Fallback UX | 네트워크 실패/미설정 상태의 empty/retry/locally saved draft | mock fixture를 production 데이터처럼 보이는 fallback으로 사용하지 않는다. |

### 구체적 이행

1. App composition(`SOOMApp`)에서 `MockWorkoutHarness`로 만든 `DashboardViewModel`/`CommunityViewModel`을 production Feature root에 전달하는 관계를 제거할 후보로 표시한다. 실제 제거는 Activity/Feed가 production queries로 전환된 뒤에 한다.
2. `FeedView`의 기본 initializer에서 `FeedMockData`와 `.mockOnly`를 production default로 사용하지 않도록 한다. production container는 repository configuration을 명시 주입하고, Preview/test는 mock initializer 또는 fixture를 명시한다.
3. `FeedDataSource`의 remote failure는 mock post가 아니라 empty/retry state 또는 로컬 `FeedShareDraft`만 반환하도록 정책을 전환한다. remote feed가 아직 구현되지 않은 기간의 product 결정은 명시적 feature flag로 제한한다.
4. `RecoveryActivitySource.defaultSource`를 production composition에서 `.mock`으로 두지 않는다. 권한/데이터 가용성에 따라 `.healthKit` 또는 `.local`을 선택하고, 데이터가 없으면 Recovery empty/onboarding state를 사용한다. mock은 Preview/test injection 전용이다.
5. `RecordLaunchPlan.mockToday`는 Preview/demo launch plan으로 이름과 주입 지점을 명확히 한다. production에서는 위치, 사용자 설정, recovery input에서 구성한 launch plan을 주입한다. 단, Record 저장 모델인 `UnifiedWorkout`과 save flow는 계속 production path로 유지한다.
6. 각 mock source에는 `Mock`, `Preview`, `Fixture`, `Harness` 중 하나를 타입명 또는 파일명에 포함하고, production container에서의 참조를 lint/search review 항목으로 추가한다.

## 5. Recovery 노출 위치 결정

결정: **Recovery는 독립 root tab으로 추가하지 않는다. Feed의 최상단 weekly snapshot 바로 다음에 개인화된 recovery entry card를 두고, 상세는 기존 `RecoveryViewContainer`로 연다.**

- Feed 중심 UX에서 오늘의 피드 해석 전에 사용자의 컨디션을 제공하므로 맥락이 자연스럽다.
- 기존 `Feed` 탭의 `NavigationStack`과 `RecoveryViewContainer`를 재사용한다. 새 tab, router, navigation path를 만들지 않는다.
- Activity는 운동 기록과 추세를 보는 library로 유지하고, Recovery는 Activity 내부 root로 이동하지 않는다.
- Profile은 HealthKit 권한 및 설정 진입을 유지한다. Recovery의 primary discovery 위치가 Profile이 되지 않도록 한다.
- `HomeView`의 기존 Recovery entry는 삭제하지 않는다. root 노출이 비활성인 현 상태에서는 legacy/alternate surface로 보존하고, 중복 entry의 제품 결정은 Feed 노출 검증 후 별도 작업에서 한다.
- entry card와 detail은 production recovery provider가 준비된 이후에만 production UI로 구현한다. 이 task에서는 위치와 소유권만 확정한다.

## 검증 및 회귀 방지 계획

계획 구현 시 아래 테스트군을 우선 실행하거나 확장한다.

| 변경 영역 | 기존 검증 | 추가할 회귀 검증 |
| --- | --- | --- |
| Root/Record handoff | `RecordLaunchPlanTests`, `RecordWorkoutSaveFlowTests`, `RecordWorkoutSessionTests` | cancel/save/share 결과가 현재와 같은 탭으로 복귀하는지 coordinator 단위 테스트 |
| Activity source | `UnifiedWorkoutStoreTests`, `UnifiedWorkoutLibraryViewModelTests`, HealthKit import tests | production query가 SwiftData 결과만 사용하며 harness workout을 merge하지 않는지 |
| Feed source | `FeedDataSourceTests`, `FeedMockDataTests`, `FeedShareDraftTests` | production remote failure가 fixture post를 노출하지 않고 local draft/empty state 규칙을 따르는지 |
| Recovery source | `RecoveryDataProviderFactoryTests`, `RecoveryViewModelTests`, `HealthKitRecoverySourceSmokeTests` | production composition이 `.mock`을 기본값으로 선택하지 않는지; no-data 상태가 mock summary를 보이지 않는지 |

문서 작성 단계의 검증은 다음과 같다.

- 기존 Swift/테스트 파일은 수정하지 않는다.
- `git diff --check`로 문서 whitespace를 검증한다.
- `git diff`로 변경 범위가 이 계획 문서 하나인지 확인한다.

## 완료 기준

- `RootTabView`의 최종 책임과 Activity 분리 순서가 명확하다.
- 다섯 Feature 및 Recovery의 소유권·의존성 경계가 정의되어 있다.
- Activity의 canonical production source가 `UnifiedWorkoutStore`로 확정되어 있다.
- mock fixture/harness가 production 기본 흐름에서 분리되는 단계가 정의되어 있다.
- Recovery의 primary discovery 위치가 Feed이며, 새 root tab 또는 navigation system을 만들지 않는다는 결정이 기록되어 있다.
