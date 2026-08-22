# SOOM 출시 준비도 감사 (Launch Readiness Audit)

작성일: 2026-08-22
관점: IA(정보구조)가 아니라 **"출시해도 되는가"** — 화면이 뜨는지가 아니라 실제 프로덕션 데이터로 끝까지 동작하는지, 버튼을 누르면 실제로 뭔가 일어나는지.
방법: 코드를 직접 읽고 호출 체인을 추적해서 확인(추정/전언 배제). 판정마다 `file:line` 근거를 남김.
범위: SOOM 앱 코드(탭 5개 + Club/Settings/로그인/알림/온보딩). **App Store 제출에 필요한 비코드 항목(개인정보처리방침, 스크린샷, 앱 설명 등)은 범위 밖 — 문서 끝 별도 섹션 참고.**

이 문서는 기존 `soom-status-audit.md`(2026-08-18 작성)를 대체하지 않고 새로 작성함 — 그 문서 작성 이후 IA 수정 배치(ia-fix-q1~q5)와 Feed 상세 통합 마이그레이션(배치 1~12)이 진행돼서 상당수 항목의 상태가 바뀌었음. 옛 문서와 상충하는 부분은 이 문서가 최신.

판정 태그: **REAL**(실 데이터/실 백엔드로 끝까지 동작) / **PARTIAL**(동작은 하나 조건부로 mock 폴백되거나 일부만 실동작) / **MOCK/PLACEHOLDER**(항상 가짜 데이터거나 "준비 중" 자리표시) / **DEAD**(UI는 있으나 탭해도 아무 일도 안 일어남) / **MISSING**(관련 코드 자체가 없음)

---

## 요약 (TL;DR)

| 판정 | 내용 |
|---|---|
| ✅ REAL | Feed 프로덕션 데이터 연결(+실패 시 정상 폴백), Feed 본인글/타인글 상세 분기, Record GPS 기록→저장, HealthKit 가져오기→저장, Apple Sign In/이메일 매직링크/세션 복원/로그아웃, 로그인 상태의 Feed 배너·Record 공유 메시지 반영, Club 가입/생성/탈퇴 액션(연결된 백엔드 기준으로) |
| ⚠️ PARTIAL | Club 전체(Supabase 세션 없으면 전부 로컬 mock으로 조용히 전환, RLS/에러 시에도 무음 폴백), Settings 운동 기준값(HealthKit Zone에만 반영, Recovery/Growth엔 미반영 — 캡션이 스스로 밝힘), HealthKit 연결상태 표시(플랫폼 제약으로 정확도 미해결) |
| 🛑 DEAD/MOCK | **Feed 액션바(응원/댓글/저장) 전부 미동작**, Feed 헤더의 🔔알림·🔍검색 버튼 완전 no-op, Settings "공개 범위" 피커(저장은 되지만 공유 로직 어디서도 안 읽음 — 눌러도 아무 효과 없음), Club Challenges/Badges 진행률(항상 0/mock), Activity 탭 "최근 변화"/"자주 가는 코스"(100% 하드코딩), `SOOMFirstJourneyCard`의 모든 CTA(탭 안 됨, 장식용) |
| 🚫 MISSING | **알림 인프라 전체**(권한요청/APNs/로컬알림/알림함 전부 없음), **온보딩 플로우 전체**(첫 실행 시 설명 없이 바로 탭바), **계정 삭제 기능**(App Store 5.1.1(v) 요건 관련 실 코드 공백) |

가장 시급한 두 가지: (1) Feed의 응원/댓글/저장 버튼과 알림/검색 아이콘이 눈에 보이는데 전부 안 눌림 — 사용자가 가장 먼저 마주치는 탭에서 바로 체감되는 결함. (2) 계정을 만들 수 있는데(Apple/이메일) 지울 방법이 없음 — 심사 거부 사유가 될 수 있는 코드 공백.

---

## 1. 탭별 상세

### 피드 (Feed)

| 항목 | 판정 | 근거 |
|---|---|---|
| 프로덕션 데이터 소스 | **REAL** | `FeedViewContainer.makeProductionViewModel()`이 실 `SupabaseFeedRepository`를 연결하고, `FeedDataSource`는 네트워크 실패/빈 결과일 때만 `FeedMockData`/로컬 초안으로 폴백 — 하드코딩이 아니라 정상적인 장애 대응. |
| 본인 글 상세(전체 깊이) / 타인 글 상세(sanitize) 분기 | **REAL** | `FeedItemDetailDestination`이 `item.sourceWorkoutId`를 로컬 SwiftData에서 조회해 분기 — 배치 10에서 만든 원래 설계 그대로 동작 확인. |
| Record → Feed 공유 플로우 | **REAL** | `FeedShareDraftBuilder`가 원격 Supabase insert 우선 시도, 실패 시(세션 없음/RLS/네트워크) 로컬 파일 폴백 — 데이터 유실 없음. |
| **액션바 (응원/댓글/저장)** | **DEAD** | `FeedItemCard.swift:642` — `FeedReferenceAction`이 그냥 `Label`이고 `Button`도 `.onTapGesture`도 없음. 셋 다 눌러도 아무 반응 없음. |
| 좋아요/댓글 쓰기 백엔드 자체 | **MISSING** | `FeedReactionDTO`/`FeedCommentDTO`는 조회(`.select`)만 있고, 리포지토리 어디에도 insert 경로가 없음 — 버튼을 지금 당장 연결해도 쓸 백엔드 메서드가 없음. |
| 헤더 🔔 알림 버튼 | **DEAD** | `FeedView.swift:164-175`, `Button(action: {})` — 빈 클로저. |
| 헤더 🔍 검색 버튼 | **DEAD** | 같은 `headerIconButton` 헬퍼 재사용, 마찬가지로 빈 클로저. |
| "더보기"(···) 버튼(카드별) | **DEAD** | `FeedItemCard.swift:70`, `Button(action: {})`. |
| `SOOMFirstJourneyCard`(빈 상태 CTA) | **DEAD/장식용** | `SoomCard.swift:175-260` — `SOOMFirstJourneyAction`에 액션 클로저 필드 자체가 없고, 렌더링도 평범한 `HStack`(Button/NavigationLink/탭제스처 없음). "첫 운동 가져오기"/"추천 코스 보기"/"천천히 맞는 클럽 찾기" 전부 눌리지 않는 텍스트. Feed뿐 아니라 이 컴포넌트를 쓰는 모든 화면(Activity/Club/Profile 빈 상태)에 동일하게 적용됨. |

### 활동 (Activity) / 기록 (Record)

| 항목 | 판정 | 근거 |
|---|---|---|
| GPS 기록(Record) | **REAL** | `RecordLocationManager`가 실 `CLLocationManager` 델리게이트로 동작. |
| 기록 저장 → UnifiedWorkout | **REAL** | `RecordWorkoutSaveFlow.save(_:)` → `store.saveWorkout(workout)`, `RecordView.swift`가 실 `SwiftDataUnifiedWorkoutStore(modelContext:)`로 배선(1516, 1665행). |
| HealthKit 가져오기 | **REAL** | `HealthKitWorkoutImportPipeline`이 실 `HealthKitWorkoutFetcher`(HKHealthStore 기반)로 가져와 실 `SwiftDataUnifiedWorkoutStore`에 저장, 중복탐지 로직까지 포함. `HealthKitWorkoutImportViewContainer`가 프리뷰 mock이 아니라 이 실 파이프라인을 실제로 연결. |
| HealthKit 권한 요청 | **REAL** | `HealthKitManager.requestAuthorization()`이 실 `HKHealthStore.requestAuthorization(toShare:read:)` 호출(프리뷰용 빈 mock과는 별개 실제 구현). |
| "오늘"/"운동 목록" 탭의 실 워크아웃 목록·상세 | **REAL** | Phase A/B 배치(1~12)로 검증 완료 — `WorkoutDeepDetailView` 계열 전부 실 `UnifiedWorkout`/route/HealthKit 스트림 소비. |
| RootTabView "최근 변화" 섹션 | **MOCK/PLACEHOLDER** | `RootTabView.swift:790-795` — `ActivityDirectionPill(title: "꾸준함", value: "↑", ...)` 등 고정 문자열, 데이터 바인딩 자체가 없음(이전 IA 감사에서 발견된 상태 그대로 유지). |
| RootTabView "자주 가는 코스" 섹션 | **MOCK/PLACEHOLDER** | `RootTabView.swift:802-807` — "한강 북단"/"탄천"/"북악" + "12회"/"8회"/"3회" 전부 하드코딩. |

### 클럽 (Club)

| 항목 | 판정 | 근거 |
|---|---|---|
| 클럽 목록/생성/가입/탈퇴 | **PARTIAL** | `ClubServiceResolver.makeDefaultService`가 `authViewModel.session.currentUser?.authProvider == .supabase`일 때만 실 Supabase 경로(`SupabaseClubService` → `FallbackClubService`로 감쌈)를 쓰고, 그 외(로그인 안 한 기본 상태 포함 — 앱의 기본 상태)엔 `InMemoryClubService`(UserDefaults 기반 순수 로컬)로 감. 버튼 자체는 각 경로에서 실제로 동작(스텁 아님). |
| Supabase 실패 시 폴백 | **PARTIAL/위험** | `FallbackClubService`가 모든 메서드에서 `try primary catch { try fallback }` — Supabase 쪽 어떤 에러든 사용자에게 티 안 나게 로컬 mock으로 넘어감. `club_foundation_v1.sql`이 "앱이 자동 적용하지 않음"으로 문서화돼 있어(`docs/SOOM_TESTFLIGHT_READINESS.md:439`), 실제 프로덕션 Supabase 프로젝트에 이 스키마가 적용됐는지는 코드만으론 확인 불가 — 안 됐다면 로그인한 사용자도 전부 조용히 로컬 mock을 보게 됨. |
| Challenges 진행률 | **MOCK/PLACEHOLDER** | `SupabaseClubService.makeChallenge(_:)`(`ClubDomainFoundation.swift:1356-1370`)가 실 Supabase 행을 매핑하면서도 `currentValue: 0`을 무조건 하드코딩 — `club_challenges` 테이블에 진행률 컬럼 자체가 없음(오늘 별도로 확인한 사실과 일치). |
| Badges | **MOCK/PLACEHOLDER** | `makeBadge(_:)`(1372-1384)도 동일 패턴 — `state: .locked, progress: 0, subtitle: "준비 중"` 무조건 하드코딩. |
| 초대/멤버 관리 | **PLACEHOLDER(자기고지)** | 관련 코드 자체가 없음. UI가 정직하게 "초대와 멤버 관리는 곧 더 자세히 연결됩니다"라고 명시(`ClubsView.swift:1027`) — 숨겨진 결함이 아니라 스스로 밝힌 로드맵. |

### 설정 (Settings)

| 항목 | 판정 | 근거 |
|---|---|---|
| 계정 연결/해제, 표시 이름, 로컬 세션 초기화 | **REAL** | `SettingsView.swift:88-161`이 전부 실 `AuthViewModel` 메서드 호출. |
| **계정 삭제** | **MISSING** | 전체 리포 검색 결과 `deleteAccount`/"계정 삭제"/"데이터 삭제" 관련 코드 0건. "계정 연결 해제"(원격 세션만 해제, 로컬 데이터는 유지)만 존재 — Apple/이메일 계정 생성을 지원하는 이상 App Store 심사 가이드라인 5.1.1(v)이 요구하는 앱 내 계정 삭제 경로가 현재 없음. |
| HealthKit 연결(⚙️→Connections) | **PARTIAL** | 실제 화면(`HealthKitSettingsViewContainer`)으로 연결되긴 하나, 연결 상태 표시 자체의 정확도는 미해결 — `authorizationStatus(for:)`가 read 권한에 대해 OS 차원에서 신뢰할 수 없다는 설계 이슈가 이전 세션에서 제기된 뒤 아직 해결 안 됨. |
| 운동 기준값(최대 심박/FTP) | **PARTIAL** | 저장은 실제로 됨(`TrainingSettingsStore`→UserDefaults)이고 `HealthKitMetricZoneBuilder`가 실제로 소비해 HealthKit 워크아웃의 Zone 분석에 반영됨(`HealthKitMetricZoneBuilder.swift:20,65`) — 단, 캡션이 스스로 밝히듯 Recovery/Growth 공식 계산에는 아직 미반영. |
| **공개 범위(privacy default) 피커** | **DEAD(기능적으로)** | `privacyDefault`가 UserDefaults에 저장은 되지만, 리포 전체에서 이 값을 읽는 공유 관련 코드(`RecordShareDraftBuilder`/`ShareCardComposer` 등)가 0건 — 피커를 조작해도 실제 공유 동작에 어떤 영향도 없음. UI는 정상 작동하는 것처럼 보여서 "아직 미연결"보다 나쁜 상태(사용자가 설정했다고 믿게 됨). |
| 알림 설정 섹션 | **PLACEHOLDER(자기고지)** | "아침 체크인과 주간 리듬 알림을 담을 자리입니다" / "알림 설정 준비 중"(`SettingsView.swift:255-257`) — 뒤에 아무 코드도 없지만 UI가 정직하게 명시. |
| 프로토타입 섹션 | 범위 밖 | `#if DEBUG` 가드 — 릴리스 빌드엔 안 실림. |

### 로그인 (Auth)

| 항목 | 판정 | 근거 |
|---|---|---|
| Apple Sign In | **REAL** | `SOOMApp.swift:12-31`이 실 `SupabaseAuthProvider`를 연결, 내부적으로 실 `client.auth.signInWithIdToken(...)` 호출. |
| 이메일 매직링크 | **REAL** | `EmailAuthViewModel.submit()` → `client.auth.signInWithOTP(...)`. |
| 이메일 비밀번호 로그인 | **DEAD CODE(무해)** | `SupabaseAuthProvider.signInWithEmail(_:)`이 조건 없이 `.futureRemoteAuthNotConfigured`를 throw — 단, 앱 어디서도 호출 안 됨(매직링크만 씀). 지금 당장 문제는 아니지만 나중에 비밀번호 로그인 UI를 이 메서드에 연결하면 항상 실패함. |
| 재실행 시 세션 복원 | **REAL** | `SupabaseAuthSessionProbe`가 Supabase SDK 자체의 Keychain 세션을 읽음(앱 자체 저장소 아님 — 아래 참고). |
| 앱 자체 `AuthSessionStore` | 참고사항 | UserDefaults 기반, 로컬 전용(비로그인) 사용자의 표시 이름만 미러링 — 실 인증 토큰은 여기 안 있고 Supabase SDK가 별도로 Keychain에 보관. |
| 로그아웃 분기 | **REAL, 정상** | Supabase 로그인 사용자는 `disconnectRemoteAccount()`(실 `client.auth.signOut()`)만 노출, 로컬 전용 사용자만 `signOut()`(로컬 미러 초기화) 노출 — 두 메서드 이름이 비슷해 헷갈릴 수 있으나 실제 배선은 정확. |
| 로그인 상태의 다른 화면 반영 | **REAL** | Feed 로그인 유도 배너(`!authViewModel.session.isSignedIn`), Record 공유 완료 메시지가 `postedRemotely` 기준 분기 — ia-fix-q5에서 만든 배선 그대로 유지 확인. |
| 게스트(로컬 전용) 경로 | **REAL** | `continueAsLocalUser()`로 인증 전체를 건너뛰고 SwiftData 기반으로 앱 전체 사용 가능. |

### 알림 (Notifications)

| 항목 | 판정 | 근거 |
|---|---|---|
| 알림 인프라 전체 | **MISSING** | `UNUserNotificationCenter`/`APNs`/`registerForRemoteNotifications`/`didReceiveRemoteNotification`/`PushKit`/`pushToken`/`deviceToken` — 리포 전체 검색 0건. 권한요청도, 로컬 알림 스케줄링도, 알림함 화면도 전무. |
| Feed 🔔 아이콘 | **DEAD** | 위 Feed 섹션 참고 — 완전 no-op. |

### 온보딩 (Onboarding)

| 항목 | 판정 | 근거 |
|---|---|---|
| 온보딩 플로우 | **MISSING** | "onboarding"/"Onboarding" 전체 검색 0건. 첫 실행 사용자가 아무 설명 없이 바로 5탭 탭바로 진입. |
| 권한 요청 시점 | **전부 지연 요청(proactive 아님)** | HealthKit은 사용자가 설정에서 직접 눌러야만 요청(`HealthKitSettingsViewModel.requestAuthorization()`), 위치 권한도 Record 세션을 실제로 시작해야만 요청(`RecordLocationManager`) — 앱 차원의 사전 온보딩 시퀀스는 없음. |

---

## 2. App Store 제출 — 비코드 항목 (이 감사 범위 밖, 별도 확인 필요)

요청대로 조사하지 않았음. 아래는 이 감사 중 발견한 것 중 App Store 제출과 맞닿아 있어 참고로 남기는 항목뿐 — 실제 준비 상태(정책 문서 작성 여부, 스크린샷, 앱 설명, 심사 메타데이터 등)는 별도로 확인 필요:

- **계정 삭제 코드 공백**(§Settings) — 이건 코드 항목이지만 App Store 심사 가이드라인 5.1.1(v)와 직결되니 비코드 체크리스트를 만들 때 같이 챙길 것.
- Apple/이메일 로그인을 지원하므로 개인정보처리방침 URL이 앱 메타데이터에 필요(Info.plist/App Store Connect 양쪽 확인 필요, 이번 조사에서 확인 안 함).
- HealthKit 사용 목적 고지 문구(`NSHealthShareUsageDescription` 등)가 Info.plist에 있는지도 이번엔 확인 안 함 — 코드 리뷰가 아니라 별도 확인 요청.
