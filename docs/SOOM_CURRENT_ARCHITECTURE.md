# SOOM Current Architecture

작성일: 2026-07-21  
분석 범위: 현재 `SOOM.xcodeproj`, `SOOM/`, `SOOMTests/`의 정적 분석  
원칙: 새 프로젝트 생성, UI/Production Feature 변경, 전체 rewrite, 기존 기능 삭제 없이 현재 구현을 기준으로 정리한다.

## 1. 요약

SOOM은 iOS 18+ SwiftUI 단일 앱 타깃이며, `App / Features / Components / DesignSystem / Models / ViewModels / Harnesses`로 나뉜 feature-oriented monolith 구조다. 화면은 SwiftUI, 로컬 영속성은 SwiftData, 운동 데이터는 `UnifiedWorkout` read model과 저장소 계층, 외부 데이터는 HealthKit·Supabase·Mapbox/OpenWeather adapter를 통해 연결된다.

확정된 다섯 목적지 `Feed / Activity / Record / Club / Profile`은 이미 `RootTabView`에 존재한다. 현재 실제 배열도 `Feed → Activity → Record → Club → Profile`이다. Record는 일반 탭 콘텐츠가 아니라 커스텀 탭바의 중앙 action이 `fullScreenCover`를 여는 구조다. 앱 시작 선택지는 Feed다.

현 단계의 핵심 과제는 새 기반을 만드는 것이 아니라 다음 세 가지다.

1. `RootTabView.swift`에 집중된 Activity와 전역 navigation 코드를 feature/router 단위로 점진 분리
2. mock/harness 데이터와 SwiftData/remote production 데이터 경계를 명시적으로 정리
3. 이미 존재하는 SOOM 토큰·공용 컴포넌트를 유지하면서 다섯 destination의 정보 구조와 상태 처리 일관성 확립

## 2. 현재 구조

```text
SOOMApp (@main)
├─ 앱 전역 객체
│  ├─ DashboardViewModel (MockWorkoutHarness)
│  ├─ CommunityViewModel (MockWorkoutHarness)
│  ├─ AuthViewModel / RootAuthBootstrap
│  └─ AuthCallbackHandler (Supabase)
├─ SwiftData ModelContainer
│  ├─ CheckInRecord
│  ├─ DailyRecoverySnapshotRecord
│  ├─ UnifiedWorkoutRecord
│  └─ PersistedWorkoutRoute
└─ RootTabView
   ├─ Feed → FeedView
   ├─ Activity → ActivityView (RootTabView 내부 private type)
   ├─ Record → fullScreenCover → RecordView
   ├─ Club → ClubsView
   └─ Profile → SettingsView
```

### 디렉터리 책임

| 영역 | 현재 책임 | 평가 |
|---|---|---|
| `SOOM/App` | 앱 진입, 전역 dependency 생성, root navigation | 올바른 위치이나 `RootTabView.swift`가 과대함 |
| `SOOM/Features` | Auth, Feed, Activity, HealthKit, Recovery, UnifiedHealth, Workout, Profile/Club, Settings | 기능 분리는 광범위하게 되어 있음 |
| `SOOM/Components` | SOOM 공용 surface와 도메인 카드 | 재사용 기반이 충분함. 일부 도메인 전용 카드는 feature 귀속 검토 가능 |
| `SOOM/DesignSystem` | 색상, 서체, 간격, radius, icon, motion/haptics | 브랜드 UI foundation이 이미 구현됨 |
| `SOOM/Models`, `ViewModels` | 초기 Workout/Community 모델 및 harness 기반 VM | 신규 UnifiedHealth 계층과 병존하는 legacy 축 |
| `SOOM/Harnesses` | mock workout 공급 | Preview/test/prototype에는 유효하나 production root에서 사용 중 |
| `SOOMTests` | 도메인 builder, persistence, import, auth, feed, record 등 단위 테스트 | 기능별 회귀 보호 범위가 넓음 |

### 데이터 흐름

- 운동의 로컬 canonical 저장 경로는 `UnifiedWorkout` → `UnifiedWorkoutPersistenceMapper` → `UnifiedWorkoutRecord` → `SwiftDataUnifiedWorkoutStore`다.
- route는 `PersistedWorkoutRoute`와 `SwiftDataWorkoutRoutePersistenceStore`로 분리 저장된다.
- HealthKit import는 UnifiedWorkout으로 변환·중복 제거·저장하는 별도 pipeline을 가진다.
- GPX/FIT/TCX route parser와 attachment service가 기존 운동에 route를 결합한다.
- Recovery check-in과 daily snapshot은 별도 SwiftData record/store를 사용한다.
- Feed는 repository/data-source abstraction과 Supabase 구현을 보유하지만, 현재 `FeedView` 기본 생성자는 `.mockOnly` 전략이다. 로컬 share draft는 병합된다.
- Club은 `ClubService` abstraction 아래 Supabase, fallback/local, in-memory 구현을 가진다.
- Auth는 local-first session과 Supabase 연결을 함께 지원한다.

## 3. App 진입점

- 파일: `SOOM/App/SOOMApp.swift`
- 진입 타입: `@main struct SOOMApp: App`
- root view: `RootTabView()`
- 시작 시 Supabase auth 환경을 읽고 원격 세션 bootstrap을 수행한다.
- URL callback은 `AuthCallbackHandler`가 처리한다.
- `DashboardViewModel`, `CommunityViewModel`은 현재 `MockWorkoutHarness`로 만들어져 environment object로 주입된다.
- SwiftData model container는 Recovery, UnifiedWorkout, route record를 한 컨테이너에 등록한다.
- 별도 DI container/coordinator는 없고 앱 진입점과 각 `*ViewContainer`가 composition root 역할을 나눠 가진다.

## 4. 현재 Navigation 구조

### Root navigation

- 파일: `SOOM/App/RootTabView.swift`
- `SOOMTab`의 선언/표시 순서: `feed`, `activity`, `record`, `clubs`, `profile`
- 초기 선택: `.feed`
- 각 일반 destination은 독립 `NavigationStack`을 가진다.
- 시스템 `TabView`가 아니라 `SOOMBottomTabBar` 커스텀 overlay를 사용한다.
- detail 화면은 `hidesSOOMTabBar()` modifier로 하단 탭바를 감춘다.
- Record 탭 버튼은 선택 상태를 바꾸지 않고 `fullScreenCover`를 연다.
- Record dismiss/share 완료는 Feed, 저장 완료는 Activity로 이동한다.

### 현재 destination mapping

| 확정 destination | 현재 root | 주요 하위 흐름 |
|---|---|---|
| Feed | `FeedView` | Feed detail, Workout detail, Analysis 진입 |
| Activity | `ActivityView` (root 파일 내부) | calendar/history, Workout detail, Unified Workout Library |
| Record | `RecordView` full screen | map-first launch, session, finish, save/share |
| Club | `ClubsView` | directory, club detail, ranking/challenge/badge, create/join/leave |
| Profile | `SettingsView` | identity/stats, account/auth, HealthKit/import, training/privacy/settings |

### 구조적 관찰

- 확정 IA는 이미 반영되어 있으므로 navigation 전면 교체가 필요하지 않다.
- `record` case에 대응하는 `selectedContent` 분기는 존재하지만 정상 탭 클릭 경로에서는 full-screen cover가 우선한다. 직접 상태 변경 시만 inline `RecordView`가 가능해 중복 경로가 된다.
- `RootTabView.swift`는 root routing뿐 아니라 Floating Recovery Coach, Activity 전체 화면/카드, tab bar 구현까지 포함한다.
- route enum/typed destination 기반 coordinator는 없으며 `NavigationLink`가 각 화면에 분산되어 있다.
- `HomeView`는 Recovery를 포함하지만 현재 root navigation에서 사용되지 않는다.

## 5. 기존 기능 상태

| Feature | 구현 위치 | 현재 상태 |
|---|---|---|
| Feed | `Features/Feed`, `Components/FeedItemCard.swift` | 목록, 상세, workout 연결, share draft 병합 구현. Supabase repository는 있으나 root 기본값은 mock-only |
| Activity | `RootTabView.swift`의 private `ActivityView`, `Features/UnifiedHealth`, `Features/Activity`, `Features/Workout` | 달력/최근 운동/통계/route 카드/라이브러리/상세 분석 구현. UI shell이 root 파일에 결합 |
| Record | `Features/Activity/Record*` | Mapbox/fallback map, 위치, 날씨, 종목 선택, session/HUD, route capture, finish/save/share draft 기반 구현 |
| Club | `Features/Profile/ClubsView.swift`, `ClubDomainFoundation.swift` | directory/detail/create/join/leave, ranking/challenge/badge와 Supabase/fallback service 구현 |
| Profile | `Features/Settings`, `Features/Auth`, `Features/HealthKit` | 운동 정체성/집계, 계정, 로컬 데이터 소유권, HealthKit/import, 훈련 기준, privacy/settings 구현. 이름은 아직 `SettingsView` |
| Recovery | `Features/Recovery`, Recovery 관련 Components | score/insight/recommendation/timeline/check-in/history/edit, daily snapshot/weekly summary 구현. top-level tab 아님 |
| Workout detail | `Features/Activity/DetailViews.swift`, `WorkoutDetailContent.swift`, `Features/Workout` | map sheet/standalone, 지표·split·zone·terrain·climb·comparison·progression·recovery impact·share 구현 |
| Unified health | `Features/UnifiedHealth`, `Features/HealthKit` | SwiftData store, deduplication, library, HealthKit import/preview 구현 |
| File route import | `Features/Workout`, `ActivityDetailGPXRouteImport.swift` | GPX/FIT/TCX parsing/attachment 및 detail 진입 기반 구현 |
| Auth | `Features/Auth` | local-first, Apple/email/Supabase session과 callback/bootstrap 기반 구현 |

## 6. Recovery 구현 위치

Recovery의 도메인·화면·영속성은 `SOOM/Features/Recovery`에 집중되어 있다.

- 화면: `RecoveryView`, `RecoveryViewContainer`, check-in/detail/edit/history views
- 상태: `RecoveryViewModel`, check-in view models
- 계산/해석: `RecoveryCalculator`, `RecoverySummaryComposer`, readiness/comparison/explanation/insight/timeline/weekly builders
- 공급자: `RecoveryDataProvider`, `ActivityRecoveryDataProvider`, `CombinedRecoveryDataProvider`
- activity source: mock/local/HealthKit 선택 구조
- persistence: `Persistence/`의 check-in 및 daily snapshot SwiftData store/mapper
- 공용 표현: `RecoveryScoreCard`, `DailyReadinessCard`, `RecoveryTimelineCard`, `RecommendationCard`, `CoachMessageCard` 등

주의할 점은 `RecoveryViewContainer` 기본 activity source가 현재 mock-backed 흐름을 유지한다는 점이다. production SwiftData check-in/snapshot과 mock activity가 섞일 수 있다. 또한 root의 `FloatingRecoveryCoach`는 `isGlobalFloatingCoachEnabled = false`이고 내부 summary도 `.mockToday`를 사용한다. Recovery는 구현량은 많지만 현재 확정 navigation에서 직접 노출되는 primary destination은 아니다.

## 7. Activity 구현 위치

Activity는 한 폴더가 아니라 세 계층에 걸쳐 있다.

- library shell: `SOOM/App/RootTabView.swift` 내부 private `ActivityView` 및 Activity 전용 private cards
- 상세 presentation/Record 일부: `SOOM/Features/Activity`
- workout 해석 도메인: `SOOM/Features/Workout`
- canonical library/persistence: `SOOM/Features/UnifiedHealth`
- legacy/display workout source: `DashboardViewModel` + `MockWorkoutHarness`

현재 Activity 목록은 SwiftData에서 최근 180일 `UnifiedWorkout`을 읽고 harness의 `Workout`과 합쳐 표시한다. legacy Workout은 상세로 직접 이동하지만 UnifiedWorkout 항목은 주로 library로 이동하므로 동일한 목록 안에서도 destination 깊이가 다르다. 이 병존은 UX Foundation 작업 전 가장 먼저 명시해야 할 데이터/라우팅 경계다.

## 8. Record 구현 위치

Record는 현재 `SOOM/Features/Activity` 아래에 있다.

- main surface: `RecordView.swift`
- map: `RecordMapView`, `RecordMapCameraState`, `RecordMapControls`
- location: `RecordLocationManager`, `RecordLocationState`
- launch/weather/layout: `RecordLaunchPlan`
- session/route capture/HUD: `RecordWorkoutSession`
- persistence mapping/save: `RecordWorkoutSaveFlow`

저장은 `UnifiedWorkoutStore`로 이어지고 완료 후 Activity로 복귀한다. 위치 권한이 없어도 time-first session을 시작할 수 있으며 지도는 Mapbox token 유무에 따라 fallback surface를 가진다. 기능을 재작성하기보다 현재 state machine과 save boundary를 보존해야 한다.

## 9. Profile 구현 위치

root의 Profile destination은 `SOOM/Features/Settings/SettingsView.swift`다. Profile UI와 settings/account/device 기능이 하나의 긴 화면에 함께 있다.

- identity/hero와 운동 집계: `ProfileSummaryCard`, `ProfileWorkoutAggregation`, `ProfileIdentitySystem`
- 설정 상태: `SettingsViewModel`, `TrainingSettings`, `TrainingSettingsStore`
- 인증/계정: `Features/Auth`
- HealthKit 연결/import: `Features/HealthKit`
- privacy/local ownership: Settings와 Auth ownership 타입

기존 기능을 삭제하지 않고, 향후 `ProfileView` shell 아래 identity 우선 섹션과 settings 하위 destination을 분리하는 방식이 적합하다. Club은 디렉터리상 Profile 아래 있지만 확정 IA에서는 독립 Club destination이므로 폴더 책임도 추후 정리 대상이다.

## 10. 재사용 가능한 코드

### 브랜드 foundation

- `SOOMColor`, `SOOMFont`, `SOOMLayout`, `SOOMRadius`, `SOOMIcon`, `SOOMMotion`, `SOOMHaptics`
- Light Mode only 정책과 semantic color/typography 원칙
- `SOOMScreen`의 safe-area/background/scroll/bottom overlay 처리

### 범용 컴포넌트

- surface/layout: `SOOMCard`, `SOOMSectionHeader`, `SOOMFirstJourneyCard`
- action/metric: `SOOMActionRow`, `SOOMIconButton`, `SOOMMetricPill`, `SOOMMetricRing`, `SOOMMetricRow`, `FlowTags`
- workout/recovery/insight 카드군은 모델 입력을 유지한 채 destination별 조합에 재사용 가능
- custom tab bar와 tab visibility modifiers는 시각 QA 후 유지 가능

### 데이터와 도메인

- `UnifiedWorkout`/store/mapper/dedup pipeline
- HealthKit import 및 metric/route mapper
- GPX/FIT/TCX parser와 route attachment service
- workout detail builder 전체(성장, 비교, 코스, terrain, split, zone, recovery impact)
- Record session/state/save flow
- Recovery calculator/provider/store/builder
- Feed/Club/Auth repository/service protocol과 fallback 구현

## 11. 신규 추가 필요 Feature

“신규”는 기존 기능 대체가 아니라 현재 구현 위에 필요한 얇은 구조를 뜻한다.

1. `AppNavigation` 또는 동등한 typed route 정의: deep link, selected tab, Record modal 결과를 한곳에서 표현
2. 독립 `ActivityView` feature shell: root 파일의 private 구현을 이동하되 동작은 그대로 유지
3. Profile shell과 Settings 하위 화면 경계: identity/history/trust를 우선하고 기존 설정은 보존
4. production dependency composition: mock/SwiftData/remote source 선택을 앱 시작 시 명시
5. 공통 loading/empty/error/offline 상태 패턴
6. Feed remote 활성화 정책 및 fallback 표시/관측성
7. UnifiedWorkout에서 동일 Workout Detail로 바로 진입하는 일관된 adapter/route
8. Recovery coach의 실제 data provider 연결 정책과 노출 위치 결정
9. navigation/UI 회귀 테스트와 핵심 5 destination smoke test

## 12. Navigation 변경 계획

### Phase 0 — 동작 고정

- 현재 다섯 destination 및 Record 결과 routing에 대한 테스트/스크린 기준을 만든다.
- 표시 순서는 확정안인 `Feed → Activity → Record → Club → Profile`을 유지한다.
- 현재 `NavigationLink` destination과 tab-bar hide 조건을 목록화한다.

### Phase 1 — 구조만 분리

- `SOOMTab`, tab bar, navigation state를 `App` 계층의 작은 파일로 분리한다.
- `ActivityView`와 Activity 전용 private components를 `Features/Activity`로 이동한다.
- 이 단계에서는 레이아웃, copy, 데이터 source, production behavior를 바꾸지 않는다.

### Phase 2 — route 일관성

- Feed/Activity/Club/Profile의 stack path와 Workout Detail route를 typed destination으로 통합한다.
- Record는 중앙 full-screen action이라는 현재 UX를 유지하고 dismiss/save/share 결과만 router event로 정리한다.
- 사용되지 않는 inline `.record` content 경로는 기능 삭제 없이 도달 가능성부터 검증한 뒤 정리한다.

### Phase 3 — 정보 구조 정돈

- Activity는 history/library 우선, 상세에서 analysis를 progressive disclosure한다.
- Profile은 identity/trust 우선, 설정과 import/device는 하위 depth로 이동한다.
- Recovery는 독립 탭으로 추가하지 않고 Feed/Profile/Workout Detail과 coach layer 중 실제 데이터가 준비된 지점에 연결한다.

## 13. 변경 필요 영역 분류

| 분류 | 영역 | 권장 조치 |
|---|---|---|
| 유지 | SwiftData UnifiedWorkout/route 저장, HealthKit/import, Record session/save, workout builders | 기존 계약과 테스트 보존 |
| 유지·확장 | DesignSystem 토큰, SOOMScreen/Card/Metric/Action 컴포넌트 | 새 화면도 토큰 우선 사용, 필요한 state variant만 추가 |
| 점진 분리 | `RootTabView.swift` | routing, Activity, floating coach, tab UI를 작은 책임으로 분리 |
| 경계 정리 | Dashboard harness Workout vs UnifiedWorkout | 하나를 삭제하지 말고 adapter와 source-of-truth 방향을 정의 |
| 경계 정리 | `SettingsView`가 Profile root 역할 | Profile shell과 settings depth를 분리 |
| 경계 정리 | Club 코드가 `Features/Profile`에 위치 | 독립 destination 책임에 맞게 추후 이동 검토 |
| production 확인 | Feed `.mockOnly`, Recovery mock activity, root harness VMs | 환경별 dependency 선택과 fallback 정책 명시 |
| 신규 | typed navigation, 공통 async state, smoke/navigation tests | 기존 UI 위에 얇게 추가 |

## 14. 위험 요소

1. **혼합 source of truth**: Activity가 SwiftData UnifiedWorkout과 mock harness Workout을 합친다. 중복, 통계 왜곡, 서로 다른 상세 destination이 발생할 수 있다.
2. **production/mock 경계 불명확**: root VMs, Feed, Recovery coach/provider에 mock이 남아 있어 UI 완성도와 실제 데이터 준비도를 혼동하기 쉽다.
3. **RootTabView 과대화**: root navigation 변경이 Activity UI와 floating coach에 동시에 영향을 줄 수 있다.
4. **Record 이중 경로**: enum case는 일반 destination처럼 보이지만 실제 클릭은 modal action이다. 상태 복원/deep link에서 inline 경로와 충돌할 수 있다.
5. **분산 navigation**: destination 생성이 각 View에 직접 있어 deep link, state restoration, analytics, 공통 transition 적용이 어렵다.
6. **Profile/Settings 결합**: 긴 단일 화면이 profile identity와 관리 기능의 우선순위를 흐린다.
7. **Recovery 노출 불일치**: 풍부한 구현에 비해 root 진입은 비활성이고 mock summary가 남아 있다. UI만 먼저 활성화하면 신뢰 문제가 생긴다.
8. **외부 서비스 구성 의존**: Supabase, Mapbox, OpenWeather, HealthKit 권한/키 부재 시 fallback이 작동하지만 환경별 UX 확인이 필요하다.
9. **대형 파일과 private type**: `RootTabView`, `RecordView`, `ClubDomainFoundation`, `SettingsView`의 크기가 변경 충돌과 리뷰 비용을 키운다.
10. **문서와 코드 drift**: README의 옛 탭 설명과 현재 확정 IA가 다르다. 이후 foundation 변경은 IA/design 문서와 함께 관리해야 한다.

## 15. 권장 착수 순서

1. 현재 navigation 및 data-source 회귀 테스트 추가
2. UI 변화 없이 `ActivityView`와 root navigation 책임 분리
3. UnifiedWorkout → Workout Detail 직접 진입 경로 통일
4. Profile shell/Settings depth 설계
5. Feed·Recovery·root harness의 production dependency 정책 확정
6. 이후에만 Strava 수준의 hierarchy, interaction, visual refinement를 destination별로 적용

이 순서는 기존 기능과 저장 계약을 보호하면서 UX Foundation을 쌓는 방식이며, 전체 rewrite나 새 프로젝트가 필요하지 않다.
