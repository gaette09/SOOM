# SOOM IA/네비게이션 진단

작성일: 2026-08-19
분석 범위: `SOOM.xcodeproj`, `SOOM/` 코드 정적 분석 + 실제 네비게이션 코드 추적
방법: 코드를 직접 읽고 함수 호출·NavigationLink 체인을 끝까지 추적. 추정 배제, 모든 판단에 `file:line` 근거를 남김.
전제: `soom-feed-social-graph` 트랙(배치 1~3, MVP 컷라인)이 끝난 뒤 우선순위를 UI/IA 정리로 전환하면서 진행한 진단. **코드 수정 없음 — 진단만.**

---

## 요약 (TL;DR)

이번 진단에서 나온 5개 답 전부가 하나의 패턴으로 수렴한다: **겉으로는 하나의 기능처럼 보이는 화면/경로가 실제로는 "mock 시절에 만들어진 경로"와 "실데이터 시대에 이어붙인 경로"로 갈라져 있고, 그 이음매에서 정보가 새거나(Q1 Feed), 사라지거나(Q2 차트), 가짜로 채워지거나(Q3 Signature Routes), 잘못된 안내가 뜨거나(Q4 가져오기 카피), 아예 전달이 안 되고 있다(Q5 로그인 상태).**

| 질문 | 핵심 결론 |
|---|---|
| Q1. 운동 상세 View 몇 개? | **파일은 1개**(`WorkoutDetailView`)로 수렴하지만 도달 depth가 mock(1홉)/실데이터(2홉)로 다르고, **Feed 카드 탭은 애초에 그 게시물 상세로 안 감** — 어떤 카드를 눌러도 항상 같은 일반 분석 화면(`AnalysisViewContainer`)으로 감 |
| Q2. 차트가 왜 엉성한가? | 라이브러리는 정상(Swift Charts, 디자인 토큰 정상 사용). 문제는 `Workout(unifiedWorkout:)` 변환 어댑터가 `samples`/`splits`/`route`/`zones`를 **전부 하드코딩 빈 배열**로 만들어서, 실제 기록에서는 차트/스플릿 섹션 자체가 통째로 숨겨짐(`!samples.isEmpty` 게이트) — mock 데모 화면과 비교되면서 완성도 격차로 느껴짐 |
| Q3. Profile 섹션 분류 | 12개 섹션 중 5개는 정체성, 7개는 설정 성격. 다만 정체성 섹션 중 **Signature Routes는 100% 하드코딩**(Activity 탭의 "자주 가는 코스"와 동일 패턴), Connections 카드도 상태값이 가짜 |
| Q4. "가져오기" 재진입 | **배선 실수 쪽.** Record로 직접 기록한 운동까지 출처 구분 없이 전부 "가져온 운동 기록"(HealthKit 전용 카피) 목록 화면을 거치도록 라우팅됨 — 미완성 마이그레이션 흔적 |
| Q5. 로그인 상태의 영향 | Auth 배관 자체(Apple Sign In, 세션)는 **진짜로 동작함**. 문제는 그 효과가 **Profile 화면 밖으로 전혀 안 새어나감** — RootTabView·Feed·Record·Activity 전부 로그인 여부를 참조 안 해서, 로그인해도 Profile 밖에서는 아무것도 안 바뀜 |

---

## Q1. "운동 상세" 화면이 실제로 몇 개의 View인가

**결론: View 파일은 정확히 1개(`WorkoutDetailView`, `SOOM/Features/Activity/DetailViews.swift:4`)뿐이다. 하지만 Feed 경로는 사실상 그 View로 가지 않는다.**

### 구조

- `WorkoutDetailView`(`DetailViews.swift:4`)는 `let workout: Workout`(레거시 mock 구조체)와 `var sourceUnifiedWorkout: UnifiedWorkout? = nil`(실데이터 override)을 동시에 들고 있는 단일 struct.
- 실제 렌더링은 `WorkoutDetailContent`(`WorkoutDetailContent.swift`)에 위임(`DetailViews.swift:38-64`).
- `WorkoutDetailView(` 호출부는 코드베이스 전체에 정확히 4곳: `RootTabView.swift:733`, `HomeView.swift:119`(고아 화면, 도달 불가), `AnalysisView.swift:95`, `UnifiedWorkoutLibraryView.swift:384`.

### 경로 1 — Activity 탭 → mock `Workout`

`RootTabView.swift:862-875` `ActivityLibraryEntry.make(from: Workout)` → `destination: .workout(workout)` → `RootTabView.swift:729-733`:

```swift
case .workout(let workout):
    NavigationLink { WorkoutDetailView(workout: workout, comparisonWorkouts: dashboardViewModel.workouts) }
```

→ **바로 `WorkoutDetailView`.**

### 경로 2 — Activity 탭 → 실 `UnifiedWorkout`(SwiftData)

`RootTabView.swift:877-888` `ActivityLibraryEntry.make(from: UnifiedWorkout)` → `destination: .library` → `RootTabView.swift:739-741`:

```swift
case .library:
    NavigationLink { UnifiedWorkoutLibraryViewContainer() }
```

→ 목록 화면으로 먼저 이동. 거기서 개별 항목 탭 → `UnifiedWorkoutLibraryView.swift:367-402` `UnifiedWorkoutDetailDestination.body`:

```swift
WorkoutDetailView(
    workout: Workout(unifiedWorkout: unifiedWorkout),   // line 604
    ...
    sourceUnifiedWorkout: unifiedWorkout,
    ...
)
```

→ **한 홉 더 들어가서 같은 `WorkoutDetailView`.** `Workout(unifiedWorkout:)` 어댑터(`UnifiedWorkoutLibraryView.swift:588-614`)가 `UnifiedWorkout` → 레거시 `Workout`으로 변환해서 먹인다.

### 경로 3 — Feed 카드 탭

`FeedView.swift:193-199`:

```swift
private func feedDestination(for item: FeedItem) -> some View {
    switch item.cardData {
    case .workoutSession:  AnalysisViewContainer()
    case .weeklyProgress:  AnalysisViewContainer()
    }
}
```

**`item` 파라미터가 스위치 분기 판별에만 쓰이고 실제로는 두 케이스 다 동일하게 `AnalysisViewContainer()`를 반환한다 — 어떤 카드를 탭하든 항상 같은 화면.** `AnalysisViewContainer`(`AnalysisViewContainer.swift:4-22`)는 인자를 하나도 안 받는 컨테이너라 애초에 "이 게시물"을 전달할 방법이 없다. 즉 **Feed 카드 탭은 그 게시물의 상세로 가지 않는다** — 매번 동일한 일반 분석 대시보드(주간 트렌드/성장/PR)로 감. `AnalysisView.swift:93-95` 안에 자체 `NavigationLink { WorkoutDetailView(workout: workout, ...) }`가 있긴 하지만, 이건 `dashboardViewModel.workouts`(mock harness 목록)를 순회하는 것이라 Feed에서 탭했던 그 항목과 무관하다.

### 요약

View는 1개(`WorkoutDetailView`)로 수렴하지만, 도달 depth가 mock(1홉)/실데이터(2홉)로 다르고, Feed는 애초에 도달 경로 자체가 끊겨 있다(탭한 아이템 무시, 매번 같은 일반 화면으로 감).

---

## Q2. 상세 화면의 그래프/차트

### 라이브러리·스타일

Apple `Charts` 프레임워크(`import Charts`), `LineMark` + `.interpolationMethod(.catmullRom)`. 커스텀 드로잉이나 서드파티 아님. 색상도 `SOOMColor.run`/`workout.sport.tint`/`SOOMColor.bike`로 디자인 토큰 정상 사용(`WorkoutMetricCards.swift:22,34,46`) — **스타일링 자체는 문제 없음.**

### 진짜 원인 — 데이터가 구조적으로 안 들어옴

`WorkoutChartStack`(`WorkoutMetricCards.swift:4-56`)과 `WorkoutSplitsCard`(`:58-75`)는 전부 `workout: Workout`(레거시 구조체)의 `.samples`/`.splits` 배열을 직접 그린다. 그런데 `Workout(unifiedWorkout:)` 어댑터(`UnifiedWorkoutLibraryView.swift:594-614`)는:

```swift
route: [],
splits: [],
samples: [],
zones: [],
```

**실 SwiftData `UnifiedWorkout`(Record로 기록했든 HealthKit으로 가져왔든, 전부)에서 변환된 모든 워크아웃은 route/splits/samples/zones가 하드코딩 빈 배열이다.** `zoneDataProvider`/`splitDataProvider`/`detailRouteOverride`처럼 실데이터를 별도 주입하는 override 파라미터가 존(zone)·스플릿·경로에는 있는데, **`samples`(차트가 그리는 원본 시계열)에는 그런 override 파라미터가 아예 없다** — `WorkoutDetailView`의 프로퍼티 목록(`DetailViews.swift:5-17`)을 봐도 samples를 주입할 방법이 없다.

다행히 완전히 깨진 빈 차트가 보이는 건 아니다 — `ActivityDetailVisibilityPolicy`(`WorkoutDetailContent.swift:1210-1216`)가 `showsCharts`/`showsSplits`를 `!workout.samples.isEmpty`/`!workout.splits.isEmpty`로 게이트해서, 실 워크아웃에서는 **섹션 자체가 통째로 숨겨진다.**

### 결론

"엉성해 보인다"의 정확한 정체는 깨진 빈 그래프가 아니라 **실제 기록에서는 그래프/스플릿 섹션이 존재 자체를 안 하고, mock harness가 만든 데모 데이터(`samples`/`splits` 꽉 채워짐)로 볼 때만 그 섹션들이 나타나서 완성도 격차가 크게 느껴지는 것**이다. 존(zone) 섹션만 `avgHeartRate > 0` 폴백(`WorkoutDetailContent.swift:1223`)이 있어 부분적으로 살아남는다.

---

## Q3. Profile 화면 섹션 분류

### 규모

`SOOM/Features/Settings/` 디렉터리: `SettingsView.swift` 794줄(그중 `body`가 `SettingsView.swift:22-49`에서 12개 섹션 함수 호출), `ProfileWorkoutAggregation.swift` 412줄, `ProfileSummaryCard.swift` 167줄, `SettingsViewModel.swift` 84줄, `TrainingSettingsStore.swift` 79줄, `TrainingSettings.swift` 36줄 — 디렉터리 합계 1,572줄. 실제 렌더링 섹션 **12개**(+조건부 온보딩 카드 1개 + 순수 헤더 텍스트 1개).

### 섹션 전수 목록 (렌더링 순서대로)

| # | 섹션 | 담당 코드 | 하는 일 | 데이터 소스 |
|---|---|---|---|---|
| 1 | Hero 카드 | `ProfileSummaryCard`(`SettingsView.swift:24-33`) | 이름/handle/정체성 문구/대표 뱃지/3개 압축 통계 | **실제** — `authViewModel.session.currentUser?.displayName`(25행), 정체성 문구는 SwiftData 집계 결과 |
| 2 | 첫 여정 카드(조건부) | `profileFirstJourneyCard`(`:34-36, 190-207`) | Health 연결/로컬 시작 유도 | 조건 로직 실제(`shouldShowProfileFirstJourney`, `:186-188`), 내용은 고정 문구 |
| 3 | 운동 성향 | `movementPatternSection`(`:37, 209-219`) | "아침형/꾸준함/주말 장거리형" 등 패턴 태그 | **실제** — `ProfileWorkoutAggregator.movementPatterns(from:)`(`ProfileWorkoutAggregation.swift:156-184`), 운동 0건이면 명시적 empty-state |
| 4 | 대표 기록 | `personalBestSection`(`:38, 221-231`) | 최장 라이딩/러닝/최고 주간거리 3개 | **실제** — `personalBests(from:)`(`:186-200`), 실측 없으면 "기록 준비 중" |
| 5 | Badge Showcase | `badgeShowcaseSection`(`:39, 245-255`) | 뱃지 4종 | **실제** — `badges(from:)`(`:281-320`), activeDays/totalDistance로 진행률 계산 |
| 6 | Signature Routes | `signatureRoutesSection`(`:40, 233-243`) | "한강 북단/탄천 루프/북악" 3개 카드 | **하드코딩/더미** — `ProfileWorkoutAggregator.profileIdentity(from:)`가 실측 대신 항상 `ProfileIdentitySystem.foundation.signatureRoutes`를 그대로 씀(`ProfileWorkoutAggregation.swift:245`). **Activity 탭의 "자주 가는 코스" 하드코딩과 동일 패턴이 Profile에도 있음.** |
| 7 | Connections | `connectionsSection`(`:41, 257-279`) | HealthKit/가져오기/Strava/Garmin/날씨 연결 카드 | **혼합** — 목록/상태값은 `ProfileIdentitySystem.foundation.connections`(`:582-587`) 하드코딩(실제 HealthKit 권한 상태 미반영). HealthKit·"운동 가져오기" 두 줄만 `NavigationLink`로 실제 화면 연결(`:261-273`) — 진입점은 진짜, 카드 상태 텍스트는 가짜 |
| 8 | "지원 영역" 헤더 | `supportAreaHeader`(`:42, 281-292`) | 순수 구분선 텍스트 | 정적, 섹션 아님 |
| 9 | 계정 | `profileSection`(`:43, 110-184`) | 로컬/원격 계정 상태, 이메일·Apple 로그인, 연결 해제 | **실제** — `authViewModel.session`, `UserOwnershipMigrationPlanner`(`:399-408`) |
| 10 | 운동 기준값 | `trainingBaselineSection`(`:44, 294-324`) | 최대 심박/FTP/단위 | **실제** — `TrainingSettingsStore`(UserDefaults 영속화) |
| 11 | 공개 범위 | `privacySection`(`:45, 326-344`) | 공유 기본값(비공개/팔로워/전체공개) | **실제** — 같은 `TrainingSettingsStore` |
| 12 | 알림 | `notificationSection`(`:46, 346-351`) | "알림 설정 준비 중" | **정적 플레이스홀더** — 로직 없음 |
| 13 | 프로토타입 | `prototypeSection`(`:47, 353-369`) | Strava Frame Lock 실험 화면 진입 | 개발자용, `#if DEBUG` 가드 없음 |
| 14 | 앱 정보 | `appInfoSection`(`:48, 371-378`) | 환경/계정 연결 상태 텍스트 | **실제** — `authEnvironment.isSupabaseConfigured` 등 실제 설정값 기반 |

### 분류

**정체성·통계 (Profile에 남을 것)**
1. Hero 카드 (실제)
2. 운동 성향 (실제)
3. 대표 기록 (실제)
4. Badge Showcase (실제)
5. Signature Routes — **단, 지금은 100% 더미라 "남기되 실데이터로 교체"가 선행돼야 함**

**계정·설정·연동 (Settings 하위로 옮길 것)**
6. 계정 (로그인/로그아웃/연결 해제)
7. Connections (HealthKit/가져오기/Strava/Garmin/날씨)
8. 운동 기준값
9. 공개 범위
10. 알림
11. 프로토타입
12. 앱 정보

### 애매한 것

- **첫 여정 카드**: 노출 위치는 Hero 카드 바로 아래(정체성 근처)지만 액션은 설정 성격. `shouldShowProfileFirstJourney` 조건("아직 로컬 데이터도 없고 계정도 없음")을 보면 정체성/설정 어느 한쪽이 아니라 **빈 상태(empty state) UI**로 별도 취급하는 게 더 정확해 보임.
- **Connections**: 카피("정체성을 보강하는 지원 영역", `:259`)는 정체성 쪽을 의도한 것 같은데, 실제 내용(권한 관리, 외부 서비스 연결)은 전형적인 설정 항목. 카드 자체가 하드코딩인 걸 고치는 김에 이 배치 결정도 같이 하는 게 맞아 보임.
- **Signature Routes**: 데이터만 놓고 보면 "정체성"이 맞는데, 완전히 가짜라서 이대로 옮기면 가짜 데이터를 정체성 섹션에 영구 고정시키는 꼴 — 이동보다 **실데이터 연결이 선행 조건**.

### 부수 확인

`ProfileIdentitySystem.foundation`(`SettingsView.swift:551-589`)은 "빈 상태 기본값"이 아니라 **탐지 실패 시 대체값이자 Signature Routes/Connections의 유일한 데이터 원천**으로 이중 역할을 함 — Hero/성향/기록/뱃지는 실측치가 이 foundation을 덮어쓰지만(`ProfileWorkoutAggregation.swift:217-249`), Signature Routes/Connections 두 필드만 덮어쓰기 로직 자체가 없다(`:245-246`에서 항상 `.foundation`을 그대로 참조).

---

## Q4. Activity 상세 진입 경로 중 "가져오기"로 빠지는 지점

### 후보 지점 전수 확인

| 위치 | 성격 | 판정 |
|---|---|---|
| `WorkoutDetailContent.swift:488-490` — "경로 파일 가져오기" 버튼 | 상세 화면 **안에서** GPX/FIT 파일 첨부하는 인라인 액션, 화면 이탈 없음 | **의도된 것** |
| `UnifiedWorkoutLibraryView.swift:80-90` — "아직 가져온 운동 기록이 없어요" | `viewModel.workouts.isEmpty`일 때만 표시되는 정상 empty-state | **의도된 것** |
| `RootTabView.swift:650-666` — "첫 운동 가져오기" 카드 | `libraryEntries.isEmpty`일 때만 표시(진짜 빈 계정) | **의도된 것** |
| `RootTabView.swift:877-890` — `ActivityLibraryEntry.make(from: UnifiedWorkout)` | 아래 상세 설명 | **배선 실수/미완성 마이그레이션에 가까움** |

### 핵심 발견 — 진짜 문제는 "가져오기 화면"이 아니라 그 앞에 낀 "라이브러리 목록" 한 겹

Activity 최근 운동 목록(`recentWorkoutSection`, `RootTabView.swift:645`)에서 항목을 탭하면 `recentWorkoutLink(for:)`(`RootTabView.swift:729-747`)가 `entry.destination`으로 분기한다 — 이미 Q1에서 확인한 그 분기와 동일:

```swift
case .workout(let workout):   // mock harness Workout
    NavigationLink { WorkoutDetailView(...) }   // 상세로 직행
case .library:                 // 실제 UnifiedWorkout (출처 무관)
    NavigationLink { UnifiedWorkoutLibraryViewContainer() }
```

`ActivityLibraryEntry.make(from: UnifiedWorkout)`(`RootTabView.swift:877-890`)는 **워크아웃 출처(Record 직접 기록 vs HealthKit 가져오기)를 구분하지 않고** 무조건 `destination: .library`를 부여한다(`:888`). 사용자가 SOOM 앱으로 직접 기록한 운동조차 상세를 한 번에 못 보고, `UnifiedWorkoutLibraryViewContainer`라는 중간 목록 화면을 한 번 더 거쳐야 한다.

이 중간 화면 자체가 문제를 키운다 — `UnifiedWorkoutLibraryView.swift`의 네비게이션 타이틀은 **"가져온 운동 기록"**(`:43`), 빈 상태 문구는 **"HealthKit 운동 가져오기를 실행하면 여기에 표시돼요"**(`:88`)로, 오직 HealthKit 임포트만 상정한 카피다. 하지만 실제로 이 목록이 읽어오는 데이터는 `store.fetchRecentWorkouts(days:)`(`UnifiedWorkoutLibraryViewModel.swift:28`)로, **출처 필터가 전혀 없어 Record로 직접 기록한 운동도 똑같이 여기 나타난다.**

### 판정 — 배선 실수 쪽

- 라우팅 자체는 끊기지 않는다(목록→탭→`UnifiedWorkoutDetailDestination`→`WorkoutDetailView`로 정상 도달) — 크래시나 데드엔드는 아님.
- "의도된 재연동 유도"라고 보기엔 근거가 없다: 데이터가 이미 있는데도(방금 Record로 저장한 운동인데도) 목적지 화면이 "HealthKit에서 가져오세요"라고 말하는 건 안내가 아니라 **오정보**에 가깝다.
- 가장 설명이 되는 시나리오: `.library` destination이 원래 "HealthKit 가져오기 결과 검토" 전용으로 만들어졌고, 이후 Record 저장 경로가 같은 `UnifiedWorkout`/`UnifiedWorkoutStore`로 통합되면서 라우팅 분기(`ActivityLibraryEntry.make`)를 손보지 않고 기존 `.library` 케이스를 그대로 재사용한 것으로 보임 — **미완성 마이그레이션 흔적.**

---

## Q5. 로그인 상태가 IA 전체에 미치는 영향

### Auth 상태 추적

`AuthSession`(`SOOM/Features/Auth/AuthSession.swift:11-38`)이 진실 소스: `sessionState` enum(`localOnly/signedOut/signedIn/loading/error`), `isSignedIn`/`isLocalOnly` 계산 프로퍼티. `AuthViewModel`(`AuthViewModel.swift:4-201`)이 `@Published session`을 들고, `SOOMApp.swift:38`에서 `.environmentObject(authViewModel)`로 전체 트리에 전파.

**중요 발견**: Apple Sign In은 실제로 완전히 동작한다. `SupabaseAuthProvider.signInWithAppleCredential`(`SupabaseAuthProvider.swift:195-218`)이 `client.auth.signInWithIdToken`을 호출해 진짜 Supabase 세션을 만든다. Supabase Swift SDK의 기본 로컬 스토리지는 `KeychainLocalStorage(service: "supabase.gotrue.swift")`로 서비스명이 고정돼 있어, 앱 어디서 `SupabaseClient`를 새로 만들든(SOOMApp/FeedViewContainer/RecordView 각각 독립 생성) **동일한 Keychain을 공유**한다. 즉 "화면마다 세션이 파편화됐다"가 아니라, **세션을 한 번도 만든 적이 없어서 공유할 게 없었다**는 게 정확한 진단 — Apple Sign In으로 한 번이라도 로그인하면 Feed/Record도 그 세션을 그대로 인식한다.

### RootTabView

재확인: `grep -c "authViewModel\|AuthViewModel" SOOM/App/RootTabView.swift` → **0**. `RootTabView.swift:614`의 `@EnvironmentObject`는 `dashboardViewModel`(harness)과 `SOOMTabBarVisibility`뿐 — 루트 네비게이션은 로그인 여부와 완전히 무관하게 동작한다(기존 감사에서 확인된 내용 그대로 유효).

### Profile/Settings — 유일하게 실제로 분기하는 화면

- `authStatusText`(`SettingsView.swift:89-95`): "계정 연결됨"(Supabase) / "로컬 사용자"(local) / "로그인 준비 중" 3단 표시.
- 분기 기준은 "로그인 여부"가 아니라 **"currentUser 존재 여부"**(`:114`): `currentUser == nil`(진짜 최초 실행)일 때만 "로컬 사용자로 계속하기" 버튼(`:118`, Supabase 호출 없음) 노출. 한 번이라도 로컬 사용자를 만들면 이메일/Apple 카드, 연결 해제, "계정 상태 확인" 등이 노출됨.
- `ClubsView.swift:68-71`도 `authViewModel.session.currentUser?.authProvider == .supabase` 여부로 실제 Supabase 서비스 vs InMemory 폴백을 전환.

### Feed — 로그인 유도 카피 0건

`FeedViewContainer.swift`는 `authViewModel`을 전혀 참조하지 않고 매번 `SupabaseClientProvider(environment: AuthEnvironmentLoader().load())`로 새 클라이언트를 만든다. Keychain 공유 덕에 세션이 있으면 인식은 되지만, **화면 어디에도 "로그인하면 다른 사람 글도 볼 수 있어요" 같은 안내가 없다.** 로그인 안 된 상태에서 조용히 mock/로컬 draft로 폴백되는 것도 사용자에게 전혀 안 드러난다.

### Record 공유 성공 표시

재확인: `RecordView.swift:1521-1536`의 `createFeedShareDraft`는 원격이든 로컬 폴백이든 성공하면 무조건 `finishSavedWorkoutFlow(shareCompleted: true)`(`:1531`) — 동일한 완료 UI. 로그인 상태를 구분하는 코드 자체가 없다.

### 종합

로그인 상태는 **"있으나 마나"가 아니라 "Profile 화면 안에서만 의미 있고, 그 밖의 모든 화면(Feed/Record/Activity/루트 탭)에서는 있으나 마나"**한 상태다. Auth 배관 자체(Apple Sign In, 세션 브릿지, Keychain 공유)는 실제로 동작하는 진짜 기능이라 "미구현"으로 뭉뚱그리면 안 된다 — 다만 그 효과가 Profile 밖으로 전혀 새어나가지 않아서, 로그인해도 Feed/Record 사용자 경험이 하나도 안 바뀌는 게 현재 IA의 실제 문제다.

---

## 관통하는 패턴

다섯 개 답을 나란히 놓고 보면 전부 같은 모양의 문제다 — **레거시 mock 경로와 실데이터 경로가 완전히 통합되지 않은 채 공존**하면서:

1. 실데이터 항목이 mock 항목보다 한 단계 더 깊이 들어가야 하거나(Q1, Q4 — `.library` 우회),
2. 실데이터 항목에서는 mock에만 있던 필드(samples)가 통째로 비어서 섹션이 사라지거나(Q2),
3. 실측이 없는 필드는 조용히 "기본값(foundation)"이라는 이름의 고정 더미로 채워지거나(Q3 Signature Routes/Connections),
4. 화면 카피가 예전 가정(HealthKit 전용)에 머물러 있거나(Q4),
5. 새로 만든 실제 기능(Auth)이 기존 화면들(RootTabView, Feed, Record)에 연결되지 않은 채 고립돼 있다(Q5).

이건 개별 버그 4~5개가 아니라, **"UnifiedWorkout으로의 마이그레이션이 화면 레이어까지는 완주되지 않았다"**는 하나의 원인이 여러 화면에서 다른 증상으로 나타난 것에 가깝다.
