# SOOM 앱 기능 현황 감사 (Status Audit)

작성일: 2026-08-18
분석 범위: `SOOM.xcodeproj`, `SOOM/`, `SOOMTests/`의 코드 정적 분석 (465개 Swift 소스 파일)
기준: "빌드되고 화면이 뜬다"가 아니라 **"실제 데이터로 끝까지 동작하는가"**
방법: 코드를 직접 읽고 함수 호출 체인을 추적해서 확인. 추정/전언 배제, 모든 판단에 `file:line` 근거를 남김.

기존 `docs/SOOM_CURRENT_ARCHITECTURE.md`(2026-07-21 작성)를 출발점으로 삼되, 이후 커밋
(`1b85442 feat(feed): add production feed foundation` 포함)과 실제 코드를 대조해 갱신했다.
본 문서와 상충하는 부분은 본 문서가 최신이며, 상충 지점은 각 섹션에 명시했다.

---

## 요약 (TL;DR)

| 판정 | 내용 |
|---|---|
| ✅ 실제로 끝까지 동작 | 운동 기록(Record) → 저장(SwiftData), HealthKit 임포트 → 저장 → Activity 노출, Workout Detail 전 계열, Club(Supabase/로컬 폴백), Auth |
| ⚠️ 부분 구현 (겉은 진짜, 알맹이 일부 가짜) | Feed 아이템 목록(Supabase 리포지토리가 코드상 존재하나 프로덕션에서 한 번도 생성되지 않음 — 항상 mock), Recovery 활동 소스 기본값이 `.mock`, Activity 탭의 "최근 변화"/"자주 가는 코스" 섹션이 100% 하드코딩 |
| 🛑 끊김/미노출 | 온보딩 플로우 자체가 없음, 앱 진입 시 인증 게이트가 없음(비로그인도 전체 탭 노출), `HomeView`는 완전 고아 화면, `FloatingRecoveryCoach`는 기능 플래그로 꺼져 있고 내부도 하드코딩 |

가장 큰 리스크는 **Feed와 Recovery다.** 둘 다 "실제 백엔드/실제 데이터로 보인다"는 인상을 주지만
실제로는 프로덕션 경로에서 mock으로 항상 대체된다 — 사용자에게 티가 나지 않는 방식으로.

---

## 1. 화면/기능 인벤토리

완성도 기준: **완전 동작**(실 데이터 소스에 연결, 프로덕션 경로에 mock 분기 없음, 로딩/에러/빈 상태 처리) /
**부분 구현**(동작은 하나 알려진 결함 — mock과 실데이터 혼합, 에러 처리 누락, 기능 플래그 비활성, 흐름 중 TODO) /
**스텁/플레이스홀더**(정적 UI 위주, 실제 내비게이션에서 도달 불가).

### Feed

| 화면 | 파일 | 완성도 | 근거 | 내비게이션 도달 |
|---|---|---|---|---|
| FeedViewContainer / FeedView | `Features/Feed/FeedViewContainer.swift:21-28`, `FeedView.swift` | **부분 구현** | `FeedViewContainer.swift:24`가 `FeedDataSource(draftStore: FileFeedShareDraftStore.live)`를 생성하며 `remoteRepository` 인자를 넘기지 않음 → 기본값 `nil` (`FeedDataSource.swift:17`). `loadFeed`는 `remoteRepository`가 존재할 때만 원격을 시도하므로(`FeedDataSource.swift:29`) 프로덕션에서는 항상 `MockFeedRepository()`로 폴백(`FeedDataSource.swift:18,43-44`). `SupabaseFeedRepository.swift`는 실재하고 단위 테스트도 있지만(`SOOMTests/FeedDataSourceTests.swift`) 앱 코드 어디에서도 생성되지 않음(grep 확인). Weekly snapshot/recovery insight 부분은 `UnifiedWorkoutWeeklyProgressProvider`/`UnifiedWorkoutRecoveryPreviewProvider`로 실제 SwiftData 기반 | 예 — 루트 탭, 기본 선택 탭 (`RootTabView.swift:53,157`) |
| Feed → Recovery 카드 | `FeedView.swift:32-40` | 부분 구현 | `recoveryInsight`가 있을 때만 `NavigationLink { RecoveryViewContainer() }` 노출. insight 자체는 실 SwiftData 기반이지만 진입한 `RecoveryViewContainer`의 activity source는 `.mock` 기본값(§Recovery 참조) | 예 |
| Feed → Workout Detail/Analysis | `FeedView.swift:197-199` | 완전 동작 | `AnalysisViewContainer()`로 실 데이터 연결 | 예 |
| Feed post detail | `Features/Feed/FeedPostDetailContent.swift` | 부분 구현 | UI 자체는 실동작하나 입력이 mock 아이템 | 예 |

### Activity

| 화면 | 파일 | 완성도 | 근거 | 내비게이션 도달 |
|---|---|---|---|---|
| ActivityView (루트 탭, private) | `App/RootTabView.swift:613-774` | 부분 구현 | `loadSavedWorkouts()`(line 769)는 실 `SwiftDataUnifiedWorkoutStore.fetchRecentWorkouts(days:180)`와 mock harness `dashboardViewModel.workouts`를 병합. `recentChangeSection`(674-684), `favoriteRoutesSection`(686-696)은 **완전 하드코딩**: `ActivityDirectionPill(title: "꾸준함", value: "↑"...)`, `ActivityRouteCard(title: "한강 북단", count: "12회"...)` — 어떤 사용자든 동일한 고정 문자열이 뜸. 데이터 기반 구현이 아예 없는 상태(폴백조차 아님) | 예, 루트 탭 |
| AnalysisView / Container | `Features/Activity/AnalysisView.swift`, `AnalysisViewContainer.swift:9-20` | 완전 동작 | `UnifiedWorkoutWeeklyProgressProvider`, `GrowthTrendProvider`, `PersonalRecordProvider`, `ProgressionIntelligenceProvider` 모두 실 `SwiftDataUnifiedWorkoutStore` 기반 | 예 |
| WorkoutDetailContent / DetailViews / MapSheet / MetricCards | `Features/Activity/*.swift` | 완전 동작 | 실 `Workout`/`UnifiedWorkout` 구조체 소비, split/zone/terrain/comparison 빌더 전용 단위 테스트 다수 | 예 |
| RecordView (Record 탭, full-screen) | `Features/Activity/RecordView.swift` | 완전 동작 | 아래 §2 Record 플로우 참조 | 예 — 탭바 중앙 액션 |
| Map (Mapbox) | `Features/Activity/RecordMapView.swift`, `Features/Workout/WorkoutDetailMapView.swift`, `MapboxStaticRouteURLBuilder.swift` | 완전 동작 (토큰 없을 때 시각적으로 구분되는 폴백) | §4 참조 | 예 |

### Record

RecordView·RecordMapView·RecordLocationManager·RecordWorkoutSaveFlow 전부 완전 동작으로 확인 — 상세는 §2 참조.

### Club

| 화면 | 파일 | 완성도 | 근거 | 내비게이션 도달 |
|---|---|---|---|---|
| ClubsView + detail/ranking/challenge/badge/create/join/leave | `Features/Profile/ClubsView.swift`(1147줄), `ClubDomainFoundation.swift`(2336줄) | 완전 동작 (정상적 온/오프라인 폴백 포함) | `ClubsView.swift:68-72`의 `.task(id: authViewModel.session.currentUser?.id)`가 `ClubServiceResolver.makeDefaultService`를 호출. Supabase 클라이언트 준비 + 실 사용자 ID 존재 시 `SupabaseClubService`를 `FallbackClubService`로 감싸 사용, 아니면 `InMemoryClubService(persistence: LocalClubPersistence())`(`ClubDomainFoundation.swift:1484-1523`). 이건 스텁이 아니라 정상적인 게스트/오프라인 폴백 패턴 | 예, 루트 탭 |

### Profile / Settings

| 화면 | 파일 | 완성도 | 근거 | 내비게이션 도달 |
|---|---|---|---|---|
| SettingsView (Profile 루트 역할 겸임) | `Features/Settings/SettingsView.swift` | 완전 동작 (집합체) | `HealthKitSettingsViewContainer()`(262행), `HealthKitWorkoutImportViewContainer()`(269행)로 실 연결 | 예, 루트 탭 |
| HealthKitWorkoutImportViewContainer | `Features/HealthKit/HealthKitWorkoutImportViewContainer.swift` | 완전 동작 | §2-6 참조 | 예 |
| HealthKitSettingsView / RecoveryPreviewView | `Features/HealthKit/*.swift` | 완전 동작 | 실 `HKHealthStore()` 사용 확인 | 예 |
| Auth (Apple/이메일 로그인, 세션 부트스트랩) | `Features/Auth/*` (33개 파일) | 완전 동작 | 실 `ASAuthorizationAppleIDCredential`, `SupabaseAuthProvider`, `AuthCallbackHandler`, 테스트 12개 파일 | 진입 게이트로만 존재(§2-1 참조 — 실제로는 게이트가 아님) |

### Recovery

| 화면 | 파일 | 완성도 | 근거 | 내비게이션 도달 |
|---|---|---|---|---|
| RecoveryViewContainer / RecoveryView | `Features/Recovery/RecoveryViewContainer.swift` | **부분 구현** | `RecoveryActivitySource.swift:6`: `static let defaultSource: RecoveryActivitySource = .mock`. 파일 자체 주석(15-17행)도 "activity source는 내부 개발 스위치이며 기본값은 기존 mock 기반 흐름을 유지한다"고 명시. Check-in 이력(`SwiftDataCheckInStore`)과 daily snapshot(`SwiftDataDailyRecoverySnapshotStore`)은 실 SwiftData이지만, 회복 점수를 만드는 activity 신호 자체가 기본적으로 가짜 | **예** — `FeedView.swift:34`의 Recovery 카드를 통해 도달 가능 (기존 아키텍처 문서는 "노출 안 됨"이라 서술했으나 이는 최신 코드와 불일치함, 본 문서에서 정정) |
| CheckInView/DetailView/EditView/HistoryView | `Features/Recovery/CheckIn*.swift` | 완전 동작 | `SwiftDataCheckInStore` 기반, 전용 테스트 4종 | 예, Recovery 플로우 경유 |
| FloatingRecoveryCoach | `App/RootTabView.swift:51,133-143,192-198` | **스텁 (하드코딩 + 비활성)** | `isGlobalFloatingCoachEnabled = false`로 `shouldShowFloatingCoach`가 항상 `false`. 활성화되더라도 `summary`는 하드코딩 `.mockToday`이고 `coachMessage`는 어떤 provider도 거치지 않는 리터럴 한국어 문자열 | **아니오** — 죽은 코드, 기능 플래그로 차단 |

### Home

| 화면 | 파일 | 완성도 | 근거 | 내비게이션 도달 |
|---|---|---|---|---|
| HomeView | `Features/Home/HomeView.swift:45` | **고아 화면** | `RecoveryViewContainer()`를 내부에 갖고 있으나, `HomeView(` 호출부를 전체 `SOOM/`에서 grep해도 **프로덕션 호출 지점 0건**. `RootTabView`나 다른 어떤 화면에서도 참조되지 않음 | **아니오** — 완전 도달 불가 |

### UnifiedHealth

| 화면 | 파일 | 완성도 | 근거 | 내비게이션 도달 |
|---|---|---|---|---|
| UnifiedWorkoutLibraryView/Container | `Features/UnifiedHealth/UnifiedWorkoutLibraryViewContainer.swift` | 완전 동작 | 실 `SwiftDataUnifiedWorkoutStore`, route persistence store, GPX/FIT/TCX attachment 연결 | 예, Activity 탭 경유 (`RootTabView.swift:714-716`) |
| UnifiedWorkoutDuplicateReviewView | `Features/UnifiedHealth/UnifiedWorkoutDuplicateReviewView*.swift` | 완전 동작 추정 | 전용 ViewModel 테스트 존재, 이번 감사에서 라인 단위 재확인은 안 함 | 예, 임포트/라이브러리 플로우 일부로 추정 |

---

## 2. 핵심 플로우 추적 (끝까지 되는가)

### 2-1. 앱 실행 → 인증 → 첫 화면

1. `SOOMApp.swift:33` — 루트 뷰는 항상 `RootTabView()`.
2. `SOOMApp.swift:38-40` — `.task`에서 `rootAuthBootstrap.bootstrap()` 실행 (`RootAuthBootstrap.swift:26-44`가 `AuthViewModel.initializeSession()` 호출).
3. `RootTabView.swift:71-176`(`body`/`selectedContent`) — **`AuthViewModel`이나 `isAuthenticated`에 대한 참조가 전혀 없음.** 인증 상태를 분기하는 코드가 tab content 어디에도 없음.
4. 시작 탭: `.feed` (`RootTabView.swift:53`).

**판정: 인증 게이트가 없다.** 세션 상태와 무관하게 앱은 항상 전체 탭바(Feed)로 바로 진입한다. Auth 자체(Apple/이메일/Supabase)는 실제로 동작하지만, 루트 뷰 트리 어디도 그 결과로 분기하지 않는다 — 로그인 여부와 무관하게 동일한 UI가 노출된다.

### 2-2. Record 운동 기록 플로우

1. Record 탭 탭 → `isRecordLaunchPresented = true` → `fullScreenCover`로 `RecordView` (`RootTabView.swift:91-130`).
2. `startWorkout(with:)`(`RecordView.swift:619`) — 실 `RecordLocationManager`(`CLLocationManager` 기반), `RecordMapView`로 실시간 경로 캡처 시작.
3. 종료 → `saveFinishedSession(_:)`(`RecordView.swift:1497-1514`) — `SwiftDataUnifiedWorkoutStore` + `SwiftDataWorkoutRoutePersistenceStore`로 `RecordWorkoutSaver.save(summary)` 호출. **실제 SwiftData 영속화** 확인(`RecordWorkoutSaveFlow.swift:82-86`).
4. "피드에 공유" → `createFeedShareDraft(from:)`(`RecordView.swift:1517-1532`) → `RecordShareDraftCoordinator.handle(.shareToFeed, workout:)`(`FeedShareDraftBuilder.swift:109-118`) → `FileFeedShareDraftStore.saveDraft`(`FeedShareDraftStore.swift:27-33`)가 **로컬 JSON 파일**(`Application Support/SOOM/feed_share_drafts.json`)에 기록. 네트워크 전송이 전혀 없음 — Supabase나 어떤 백엔드로도 게시되지 않으며, 같은 기기/사용자 로컬 병합으로만 보인다.
5. `WorkoutShareSheet`(실 `UIActivityViewController` 래퍼, `Components/WorkoutShareSheet.swift:7-14`)는 존재하며 `AnalysisView.swift`/`WorkoutDetailContent.swift`에서 사용됨 — 즉 네이티브 OS 공유 시트는 워크아웃 상세/분석 화면에는 연결돼 있으나, Record 종료 플로우 자체의 일부는 아니다.
6. dismiss 시 `onSaveComplete`/`onShareDraftComplete`가 `.activity` 또는 `.feed`로 복귀(`RootTabView.swift:107-127`).

**판정: 캡처+저장(SwiftData)은 실 데이터로 끝까지 동작한다.** "피드에 공유"는 이름과 달리 로컬 전용 초안 파일로 격하되며, 실제 게시(백엔드 fan-out)는 없다.

### 2-3. Activity → Workout Detail

1. `ActivityView`(private, `RootTabView.swift:613`)는 `dashboardViewModel.workouts`(mock `Workout`, `MockWorkoutHarness`)와 `savedWorkouts`(실 `UnifiedWorkout`, `SwiftDataUnifiedWorkoutStore.fetchRecentWorkouts(days:180)`, `RootTabView.swift:769-773`)를 병합한다.
2. 라우팅이 아이템 종류에 따라 갈라진다: mock `Workout` → `destination: .workout(workout)` → **바로** `WorkoutDetailView`로 이동(`RootTabView.swift:862-875, 731-738`). 실 사용자가 기록한 `UnifiedWorkout` → `destination: .library` → `UnifiedWorkoutLibraryViewContainer()` 목록으로 먼저 이동(`877-890, 739-746`), 상세 진입에 탭 한 번이 더 필요.
3. 라이브러리 목록에서 `UnifiedWorkoutLibraryView.swift:384`가 실제로 `WorkoutDetailView`를 생성하므로, 결국 실 데이터도 같은 상세 화면에 도달한다 — 단지 depth가 다르다.
4. `recentChangeSection`(674-684), `favoriteRoutesSection`(686-696)은 모든 사용자에게 동일한 하드코딩 문자열("한강 북단 12회", "탄천 8회", "북악 3회" 등)을 보여준다 — 실 이력과 무관.

**판정: Workout Detail 자체는 실 데이터로 끝까지 동작한다** (두 경로 모두 결국 `WorkoutDetailView`에 도달). 다만 Activity 화면 내 두 섹션은 장식용 스텁이고, mock/실데이터 항목의 내비게이션 깊이가 구조적으로 다르다.

### 2-4. Feed 플로우

1. `FeedViewContainer.makeProductionViewModel()`(`FeedViewContainer.swift:21-28`)이 `FeedDataSource(draftStore: FileFeedShareDraftStore.live)`를 생성 — **`remoteRepository` 인자를 전달하지 않음**, 기본값 `nil`(`FeedDataSource.swift:16-26`).
2. `FeedDataSource.loadFeed`(`FeedDataSource.swift:28-40`) — `if strategy.useRemoteWhenAvailable, let remoteRepository` 조건에서 `remoteRepository`가 항상 `nil`이므로 `strategy` 기본값이 `.remoteWithMockFallback`이어도 이 분기는 절대 실행되지 않는다. 곧바로 `fallbackFeed` → `MockFeedRepository()`/`FeedMockData.items`로 귀결.
3. `SupabaseFeedRepository`(`SOOM/Features/Feed/SupabaseFeedRepository.swift`)는 `SOOMTests/FeedDataSourceTests.swift:14,95`에서 테스트되지만 **`SOOM/` 앱 코드 어디에서도 생성되지 않는다**(grep으로 프로덕션 호출 0건 확인).
4. Record 플로우에서 만든 로컬 공유 초안은 `mergedWithDrafts`(`FeedDataSource.swift:47-56`)로 병합되므로 자신이 방금 기록한 운동은 자기 Feed 맨 위에 뜬다 — 하지만 다른 사용자의 활동은 절대 뜨지 않는다.

**판정: "production feed foundation" 커밋과 완성된 Supabase 리포지토리+테스트가 있음에도, 실제 프로덕션 컨테이너가 원격 리포지토리를 연결하지 않아 Feed는 출시 앱에서 영구적으로 mock+로컬 초안 전용이다.**

### 2-5. 온보딩

`grep -rl "Onboarding" SOOM/ SOOMTests/` → **매치 0건.** 최초 실행 화면, 권한 사전 안내(priming) 등 어떤 형태의 온보딩도 존재하지 않는다. 앱은 곧바로 탭바로 진입한다.

**판정: 온보딩 플로우 자체가 존재하지 않는다.**

### 2-6. HealthKit 임포트 플로우

1. Settings → Profile에서 도달: `HealthKitSettingsViewContainer()`(`SettingsView.swift:262`), `HealthKitWorkoutImportViewContainer()`(`SettingsView.swift:269`).
2. `HealthKitWorkoutImportPipeline.importRecentWorkouts`(`HealthKitWorkoutImportPipeline.swift:40-92`) — HealthKit에서 가져와 `store.fetchRecentWorkouts`(60행)로 로컬 중복 체크 후 `store.saveWorkouts(importableWorkouts)`(67/79행) — 주입된 **실** `UnifiedWorkoutStore`에 저장.
3. 경로(route) 영속화도 함께 실행(`persistRoutesIfAvailable`, 136행).
4. Activity의 `savedWorkouts`가 같은 `SwiftDataUnifiedWorkoutStore`를 읽으므로, 임포트된 운동은 Activity(라이브러리 경유)와 Workout Detail에 실제로 노출된다.

**판정: 실 데이터로 끝까지 동작한다.** 추적한 플로우 중 가장 견고하다.

### 2-7. Recovery 플로우

1. `RootTabView.swift:51` — `isGlobalFloatingCoachEnabled = false`, `shouldShowFloatingCoach`(133-143)가 다른 조건 검사 이전에 항상 `false` 반환.
2. 활성화되더라도 `FloatingRecoveryCoach.summary`(192-194)는 하드코딩 `.mockToday` — 실 provider와 무연결. `coachMessage`(196-198)도 어떤 데이터도 거치지 않는 리터럴 한국어 문자열.
3. Recovery는 최상위 탭이 아니다(`SOOMTab`은 `feed/activity/record/clubs/profile`만 가짐, `RootTabView.swift:5-10`).
4. 그러나 §1(Recovery, Feed) 확인대로 **`FeedView.swift:32-40`의 Recovery insight 카드가 실제 내비게이션 진입점이다** — `recoveryInsight`가 존재할 때(즉 실 SwiftData 기반 provider가 값을 반환할 때) `RecoveryViewContainer()`로 이동 가능. 다만 그 안에서 회복 점수를 구성하는 activity 소스는 기본값이 `.mock`(`RecoveryActivitySource.swift:6`).

**판정: floating coach 경로는 완전히 죽어있다(기능 플래그 비활성 + 내부 하드코딩). 반면 Feed 카드를 통한 Recovery 진입 경로는 실제로 존재하며 도달 가능하지만, 도달한 화면 내부의 활동 데이터 소스가 기본적으로 가짜다 — "화면은 뜨지만 안의 숫자가 진짜가 아닐 수 있는" 유형의 부분 구현.**

---

## 3. TODO/FIXME/스텁 코드 (grep 결과, 프로덕션 소스 한정)

범위: `SOOM/App`, `SOOM/Features`, `SOOM/Components`, `SOOM/DesignSystem`, `SOOM/Models`, `SOOM/ViewModels`, `SOOM/Harnesses` (SOOMTests 제외)

### 3-1. 명시적 TODO (5건, 전부 Recovery 부하/점수 계산식)

| 위치 | 내용 | 의미 |
|---|---|---|
| `Features/Recovery/CombinedRecoveryDataProvider.swift:30` | `// TODO: In v2, pass RecoveryInputContext into a score engine that can merge` | 회복 점수 병합 로직이 v2 이전 임시 설계 |
| `Features/HealthKit/HealthKitRecoveryActivityMapper.swift:55` | `// TODO: Replace this MVP estimate with TRIMP / HR zone based load once` | HealthKit 기반 훈련 부하가 검증 안 된 MVP 근사치 |
| `Features/Recovery/RecoveryActivityMapper.swift:131` | `// TODO: Replace this estimate with SOOM's validated TRIMP/load formula.` | 비-HealthKit 경로도 동일한 미검증 근사치 |
| `Features/Recovery/RecoveryCalculator.swift:225` | `// TODO: Replace these rule-based estimates with a validated recovery model` | 회복 점수 자체가 규칙 기반 휴리스틱이지 검증된 모델이 아님 |
| `Features/UnifiedHealth/UnifiedWorkoutToRecoveryActivityMapper.swift:56` | `// TODO: Replace this MVP estimate with TRIMP, HR zone, sport-specific` | UnifiedWorkout 경로에도 세 번째 동일 근사치가 중복 존재 |

FIXME/HACK/XXX는 프로덕션 코드에 0건.

### 3-2. placeholder/Placeholder — 대부분 정상 설계, 스텁 아님

- `FeedPhotoPlaceholder` — 사진 없는 피드 타일용 정식 모델 타입 (정상)
- `ShareableWorkoutCardView.swift`의 `statSummaryMissingMetricPlaceholder`, `ShareCardMediaPlaceholder` — 정상적인 빈 상태 렌더링
- `StravaDetailFrameLockView.swift:279-310` — 개발/레퍼런스용 레이아웃 스캐폴딩으로 보임. `RootTabView.swift`나 어떤 feature container에서도 호출부가 잡히지 않아, 실제 화면으로 연결돼 있는지 별도 확인 필요
- `AuthEnvironment.swift:61`, `RecordLaunchPlan.swift:656`, `WorkoutDetailMapView.swift:314` — 설정값이 문자 그대로 `"placeholder"`를 포함하는지 방어적으로 걸러내는 코드 (정상)
- `ClubDomainFoundation.swift:55` / `ClubsView.swift:1088-1117` — 비회원 상태의 정식 empty-state 시트 (정상)

"not implemented"/"unimplemented"/"Coming soon" 문자열은 프로덕션 코드에 0건.

### 3-3. mock/기본값 배선 — 진짜 문제 지점

| 영역 | 위치 | 내용 | 심각도 |
|---|---|---|---|
| Recovery | `RecoveryActivitySource.swift:6` | `static let defaultSource: RecoveryActivitySource = .mock` | **제품 결정 필요** |
| Recovery | `Features/Home/HomeView.swift:45` | `RecoveryViewContainer()` — override 없이 `.mock` 상속 | HomeView 자체가 고아 화면이라 영향 없음(§1 참조) |
| Recovery | `Features/Feed/FeedView.swift:34` | `NavigationLink { RecoveryViewContainer() }` — override 없음 | **출시 차단급** — Feed 카드를 탭하면 실제 사용자 회복 데이터가 아니라 가짜 activity 기반 점수가 뜬다 |
| Recovery (floating coach) | `RootTabView.swift:51,134,192-198` | `isGlobalFloatingCoachEnabled = false` + 내부 `.mockToday` | 기능이 완전히 꺼져 있어 사용자 영향 없음(코스메틱) |
| Feed | `Features/Feed/FeedView.swift:13` | `init(items: [FeedItem] = FeedMockData.items, ...)` | 코스메틱 — 실제 호출부는 `#Preview`뿐, 프로덕션은 `FeedViewContainer` 경유(§2-4 참조. 단 그 경로도 결국 mock으로 귀결되지만 원인은 이 기본 파라미터가 아니라 `remoteRepository`가 배선 안 된 것) |
| Feed | `Features/Feed/FeedDataSource.swift:7,20` | `mockOnly` 전략 존재, 기본 전략은 `.remoteWithMockFallback` | 전략 자체는 정상 설계 — 문제는 원격 리포지토리가 애초에 주입되지 않는 것(§2-4) |
| Club | `ClubDomainFoundation.swift:1484-1523` | Supabase 미준비/미인증 시 `InMemoryClubService` 폴백 | 정상 폴백, 스텁 아님 |

### 3-4. 요약 카운트

| 영역 | 마커 수(정상 폴백/플레이스홀더 제외) | 심각도 |
|---|---|---|
| Recovery (점수/부하 계산식) | TODO 5건 | 제품 결정 필요 — 회복 점수 산식 자체가 4개 파일에 중복된 미검증 MVP 근사치 |
| Recovery (데이터 소스 배선) | 프로덕션 호출부 2곳(HomeView, Feed 카드)이 `.mock` 상속 | **출시 차단급** — Feed 경유 진입 시 사용자에게 가짜 회복 데이터가 진짜처럼 보임 |
| Recovery (floating coach) | 플래그 비활성 1건 + 내부 하드코딩 | 코스메틱, 사용자 영향 없음 |
| Feed | mock 기본 배선 1건(구조적 원인) | **출시 차단급** — 피드 콘텐츠 자체가 항상 가짜 |
| Club | 0건(정상 폴백만 확인) | 해당 없음 |
| Auth, Settings/Profile, HealthKit, Activity(핵심 로직), Workout, DesignSystem, Harnesses | 0건 | 해당 없음 |

---

## 4. 외부 의존성 연동 현황

| 의존성 | 상태 | 근거 | 저하 조건 | 사용자에게 저하가 보이는가 |
|---|---|---|---|---|
| **Mapbox** | 실제 SDK 연동, 런타임에 토큰 유무로 조건부 | `import MapboxMaps`가 `RecordMapView`(`Features/Activity/RecordMapView.swift:36-65`)와 `WorkoutDetailMapView`/`SOOMMapboxRouteMap`(`Features/Workout/WorkoutDetailMapView.swift:37-53`) 구동. 실 커스텀 Mapbox Studio 스타일 ID 사용(`SOOMMapboxConfiguration.swift:5`). 토큰은 `MapboxAccessTokenAvailability.resolvedUsableToken`(`WorkoutDetailMapView.swift:292-319`)이 Info.plist `MBXAccessToken` 또는 env var에서 읽고 placeholder 문자열은 거부 | 토큰 없음/무효 시 `RecordMapFallbackSurface`(정적 일러스트+텍스트, `RecordMapView.swift:52-58`)로 대체 | **예 — 눈에 띄게 다른 화면**(정지 이미지) |
| **HealthKit** | 실제 | 실 `HKHealthStore()`가 `HealthKitManager.swift:23` 등 5개 파일에서 사용. `requestAuthorization()`이 실 `HKWorkoutType`/`HKQuantityType`에 대해 호출(`HealthKitManager.swift:31-73`). Info.plist에 실제 구체적인 사용 목적 문구 존재 | 사용자가 권한 거부 시 빈 상태(가짜 데이터 아님) | 예 — 정직하게 빈 상태 |
| **Supabase (Auth)** | 실제 | `SupabaseClientProvider`(`Features/Auth/SupabaseClientProvider.swift:25-28`)가 설정값 있으면 실 `SupabaseClient` 생성, `SOOMApp.swift:15-21`이 이를 `AuthViewModel`에 실 세션 로더로 연결 | URL/키 미설정 시 미확인 — 별도 확인 필요 | 미확인 |
| **Supabase (Club)** | 실제, 정상 폴백 포함 | `ClubServiceResolver.makeDefaultService`(`ClubDomainFoundation.swift:1484-1511`)가 준비 상태면 `SupabaseClubService`, 아니면 `InMemoryClubService` | Supabase 미준비/미인증 시 로컬 전용 | 예(오프라인/게스트 티가 남) |
| **Supabase (Feed)** | **연결 안 됨 — 항상 mock** | `SupabaseFeedRepository.swift` 실재하나 프로덕션 호출부 0건(§2-4, §3-3 참조) | 조건부 저하가 아니라 **상시** | **아니오 — 겉보기엔 실제 백엔드 피드처럼 보임, 실은 100% 로컬/mock** |
| **OpenWeather** | 실제 | `RecordLaunchPlan.swift:355,439,463`가 `api.openweathermap.org`에 실 HTTP 호출. 키는 env var 또는 Info.plist(`RecordLaunchPlan.swift:641-644`) | 호출/키 실패 시 `RecordWeatherSnapshot.fallbackClear`(98-101행, 정적 "맑음" 스냅샷) | **아니오 — 실제 맑은 날씨 값처럼 보임, 에러 상태 표시 없음** |
| **위치(CoreLocation)** | 실제 | `RecordLocationManager.swift`의 실 `CLLocationManager()`, Info.plist에 구체적 사용 목적 문구 | 권한 거부 시 위치 없이 time-first 세션(아키텍처 문서 기준, 이번 감사에서 라인 단위 재확인은 안 함) | — |
| **SwiftData** | 실제, 영구 저장 | `SOOMApp.swift:49-54`의 `.modelContainer(for:)`에 `isStoredInMemoryOnly` 오버라이드 없음 — 실 디스크 저장. `UnifiedWorkoutRecord`/`PersistedWorkoutRoute`/`CheckInRecord`/`DailyRecoverySnapshotRecord` 전부 이 컨테이너 사용 | — | — |
| **시크릿 공급 경로** | 확인됨 — 신규 체크아웃 시 Mapbox/OpenWeather가 조용히 저하 | `Config/LocalSecrets.xcconfig`(실값, `.gitignore:9`로 제외)와 `Config/LocalSecrets.example.xcconfig`(플레이스홀더 템플릿), `Config/Debug.xcconfig`(빈 기본값 + `#include?` optional include). 로컬 시크릿 파일 없이 클론하면 Mapbox/OpenWeather 키가 빈 문자열 → 지도 폴백 + 항상 맑음 날씨 | — | Mapbox는 보임(폴백 UI), OpenWeather는 안 보임(가짜 맑음) |

**후속 확인 필요:** Supabase Auth가 시크릿 미설정 시 어떻게 저하되는지(Info.plist 경로가 Mapbox/OpenWeather와 다른 별도 xcconfig 체인을 타는지)는 이번 패스에서 확정하지 못함.

---

## 5. 기존 아키텍처 문서와의 상충 지점 (정정)

`docs/SOOM_CURRENT_ARCHITECTURE.md`(2026-07-21) 대비 실제 코드에서 확인된 차이:

1. **Feed는 "기본값이 mock-only 전략"이 아니라 원격 리포지토리가 애초에 생성되지 않는 구조적 문제다.** 전략 플래그를 바꾼다고 해결되지 않는다 — `FeedViewContainer`가 `SupabaseFeedRepository` 인스턴스를 아예 만들지 않으므로, `FeedDataSource`가 원격을 "시도"할 방법 자체가 없다.
2. **Recovery는 "확정 navigation에서 노출되는 primary destination이 아니다"가 아니라, Feed 탭의 recovery insight 카드를 통해 실제로 도달 가능하다.** 다만 도달한 화면 내부 activity 데이터가 기본적으로 mock이라는 문제는 기존 문서의 우려와 방향은 같다.
3. **Activity의 "최근 변화"/"자주 가는 코스" 섹션은 기존 문서에 언급되지 않은 완전 하드코딩 스텁이다.** mock 데이터 혼합이 아니라 데이터 연결 자체가 없는 정적 UI.
4. **`HomeView`는 고아 화면임이 코드로 확정됐다**(기존 문서의 추정을 확인).

---

## 6. 10월 출시 기준 우선순위 제안

말로 판단하지 않고 위 근거만으로 도출한 순위:

1. **Feed 원격 연결** — `FeedViewContainer`에 `SupabaseFeedRepository`를 실제로 주입할지, 아니면 로컬 전용 피드로 갈지 제품 결정 필요. 현재 상태로 출시하면 "소셜 피드"라는 이름과 실제 동작(개인 로컬 초안만 보임)이 다르다.
2. **Recovery activity source 기본값** — Feed에서 도달 가능한 이상, `.mock` 기본값을 실 소스로 바꾸거나, 실 데이터가 준비 안 됐다면 Feed 카드 자체를 노출 조건에서 빼는 결정이 필요.
3. **인증 게이트 부재** — 의도된 것(게스트 우선 UX)인지 확인 필요. 의도가 아니라면 온보딩/로그인 플로우 자체가 없는 것과 함께 UX 결정 필요.
4. **Activity 하드코딩 섹션** — 실 데이터 연결이 없다면 출시 전 섹션을 숨기거나 명확한 empty-state로 교체.
5. **HomeView 정리** — 고아 코드이므로 유지보수 대상에서 제외하거나 삭제 검토.
