# SOOM IA 마이그레이션 계획 (3탭 방향 확정판)

기준 문서: `soom-original-spec.md`(PDF 판독) + `soom-spec-vs-current-diff.md`(현재 코드 대조). 2026-08-20 사용자 확정 방향을 배치 단위로 쪼갠 것 — **아직 코드 수정 없음, 이 문서는 계획만.**

## 확정된 목표 구조

새 탭 추가 없음. 현재 5개 탭바 버튼 중 "기록"은 이미 `selectedTab`을 바꾸지 않고 `fullScreenCover`를 띄우는 모달 실행 버튼이라(`RootTabView.swift:1464-1472`, 확인 완료) 실질 콘텐츠 탭은 원래도 4개였다.

| 순서 | 탭 | 목표 상태 |
|---|---|---|
| 1 | 피드 | 상단 주간요약/스트릭 헤더 + 피드 목록. 팔로우 그래프 완성 전까지 "공개 전체" 유지, 완성 시 필터 스위치만 켬 |
| 2 | 활동 | PDF "오늘"(AI코치) + 스트라바 You의 Progress를 합친 서브탭 + 기존 운동목록(Q4) 서브탭, 2개 서브탭 허브 |
| 3 | 기록 | 변경 없음(이미 모달 실행 버튼) |
| 4 | 클럽 | 변경 없음(탭 유지 확정) |
| 5 | 프로필 | 정체성만(아바타/트로피/통계 요약). 설정은 ⚙️로 완전 분리 |

## 확인된 구조적 사실 (구현 전 근거)

- `ActivityView`(`RootTabView.swift:613-`)는 `@EnvironmentObject`/`@Environment(\.modelContext)`만 쓰고 `selectedTab`에 의존하지 않음 — 서브탭으로 재배치해도 구조적 위험 없음.
- `SettingsView.swift`는 Q3에서 이미 `identityAreaHeader`(정체성 블록: Hero/첫여정/운동성향/대표기록/Badge/SignatureRoutes)와 `supportAreaHeader`(설정 블록: Connections/계정/기준값/공개범위/알림/프로토타입/앱정보) 두 구역으로 나눠져 있음 — **이 경계선을 그대로 화면 분리 기준으로 재사용**하면 됨. Q3는 틀린 방향이 아니라 이번 분리의 1단계였던 셈.
- `FeedView.swift`에 이미 `FeedWeeklySnapshotCarousel`(`FeedFoundationCards.swift:3`)이 실데이터(`UnifiedWorkoutWeeklyProgressProvider`, `FeedViewContainer.swift:35`)로 배선돼 있고 최상단(topHeader 바로 다음)에 렌더링됨 — **PDF의 "상단 주간요약"은 사실상 이미 있음.** 스트릭(연속 기록) UI만 없음.
- `RecoverySummary`(`RecoveryModels.swift:3-15`)는 단일 점수 구조 — PDF의 4지표(신체에너지/스트레스/회복/운동강도) 분리 모델이 아님. 이건 재배치로 해결 안 되는 신규 모델링 작업.

## 배치

### M1. 프로필 탭 = 정체성 화면 + ⚙️ 설정 분리

**무엇을**: `SettingsView.swift`를 둘로 쪼갠다 — (a) 프로필 탭 콘텐츠 = 현재 `identityAreaHeader` 블록(Hero/첫여정/운동성향/대표기록/Badge/SignatureRoutes)만 남기고, 우측 상단에 ⚙️ 버튼 추가. (b) 새 화면(가칭 `AccountSettingsView.swift`) = 현재 `supportAreaHeader` 블록(Connections/계정/기준값/공개범위/알림/프로토타입/앱정보) 전체를 그대로 옮김, ⚙️ 탭하면 `NavigationLink`로 진입.
**근거**: Q3가 이미 그은 경계선을 그대로 물리적 분리 기준으로 씀 — 판단 재작업 없음, 기계적 분리에 가까움.
**크기**: 중간. 새 파일 1개 + `SettingsView.swift` 축소 + `RootTabView.swift`의 `.profile` 케이스가 가리키는 View 이름 변경.
**연관 ROADMAP 항목**: `q3-signature-routes-real-data`, `q3-connections-real-status`(둘 다 blocked_by ia-fix-q3-profile-reorganization) — 이 배치 완료 후 새 파일 기준으로 재타겟팅 필요.
**검증**: 프로필 탭에 설정 섹션이 안 보이는지, ⚙️ 눌렀을 때 기존 6개 섹션이 그대로 나오는지, 기존 계정/기준값/공개범위 저장 로직이 그대로 동작하는지 시뮬레이터 확인.

### M2. 활동 탭 허브 골격 (서브탭 컨테이너, 기존 화면 재배치만)

**무엇을**: "활동" 탭에 세그먼트/서브탭 컨테이너를 새로 만들고, 기존 `ActivityView()` 전체를 "운동 목록" 서브탭 콘텐츠로 그대로 옮긴다. 다른 서브탭("오늘")은 이 배치에서는 빈 placeholder로만 둔다.
**근거**: 확인 2에서 검증한 대로 `ActivityView`는 재배치해도 안전 — 이 배치는 **동작 변경이 없는 순수 재배치**라 리스크가 가장 낮음. Q4에서 고친 라우팅(`ActivityLibraryEntry`/`recentWorkoutLink`)은 전혀 손대지 않음.
**크기**: 작음.
**검증**: "운동 목록" 서브탭이 예전 "활동" 탭과 화면상 완전히 동일하게 동작하는지(직접기록→상세, HealthKit가져오기→라이브러리 라우팅 포함, Q4 검증 항목 재확인) 시뮬레이터로 확인.

### M3. "오늘" 서브탭 MVP (기존 데이터 재사용, 신규 모델 없이)

**무엇을**: M2에서 비워둔 "오늘" 서브탭에 (a) `FeedWeeklySnapshotCarousel`과 동일한 주간 통계, (b) 기존 `RecoveryViewContainer`/`RecoverySummary`(단일 점수) 카드를 배치. PDF의 4지표 그리드는 이 배치에 **포함 안 함**(아래 M4 참고).
**근거**: 새 모델 없이 이미 있는 provider(`UnifiedWorkoutWeeklyProgressProvider`, Recovery 쪽 provider)만 재사용 — 최소 리스크로 "오늘" 자리를 비어있지 않게 채움.
**크기**: 중간.
**검증**: 활동 탭 진입 시 "오늘" 서브탭이 기본 선택되는지(또는 어느 쪽이 기본인지 결정 필요 — 아래 미결 항목 참고), 실데이터 반영 확인.

### M4. (범위 밖, 별도 이니셔티브) 4지표 대시보드 신규 구현

**무엇을**: 신체에너지(바디배터리)/스트레스(실시간)/회복(HRV)/운동강도(운동점수) 4개 축을 분리해서 계산·표시하는 새 모델+UI. `RecoverySummary`를 확장하거나 병렬 모델을 새로 설계해야 함.
**왜 이 마이그레이션에 안 넣는지**: diff 문서에서 이미 확인했듯 이건 재배치가 아니라 신규 기능(HRV 등 데이터 소스 확보 여부부터 확인 필요) — IA 재구조화 배치들과 크기·성격이 다름. M1~M3, M5~M6 끝난 뒤 별도로 규모 파악부터 다시 시작하는 게 맞음.

### M5. Feed 스트릭 헤더 추가

**무엇을**: `FeedWeeklySnapshotCarousel` 근처에 PDF의 스트릭 캘린더("Your Streak · N Weeks · Streak Activities")에 해당하는 작은 UI 신규 추가.
**근거**: 완전 신규지만 필요한 원본 데이터(운동 기록 날짜)는 이미 SwiftData에 있어 집계 로직만 새로 짜면 됨.
**크기**: 작음~중간(연속일 계산 로직 신규).

### M6. Feed 팔로우 필터 — 스위치만 배선, 기본 OFF

**무엇을**: Feed 데이터 소스에 "팔로우한 사용자만 보기" 필터를 걸 수 있는 지점(플래그 하나, 예: `FeedFollowFilterEnabled` 상수/설정값)을 만들어두되, **이번 배치에서는 항상 false로 고정** — 지금처럼 공개 전체가 계속 보임. 실제 필터링 쿼리 로직(follows 테이블 join)은 이 배치에 포함 안 함.
**왜 지금 배선만 해두는지**: 사용자가 명시한 "그래프 완성 전까지는 공개 전체 유지, 완성 시점에 필터만 켜는 단계적 적용" 요구사항을 코드에 미리 반영 — 나중에 `feed-follows-table`/`feed-follow-ui-and-visibility`(ROADMAP, 이미 unblock됨)가 끝나면 이 플래그 하나만 뒤집으면 되게.
**크기**: 작음(로직은 없고 분기점만).
**의존**: 실제 필터 ON은 `feed-follows-table` + `feed-follow-ui-and-visibility` 완료가 선행돼야 함 — 이 배치 자체는 그것들과 무관하게 지금 바로 가능.

### 클럽 — 배치 없음

이번 재구조화에서 탭 위치·내용 변경 없음(사용자 확정). Challenge 엔진 실계산(참가자/국가 순위 등)은 기존 known issue대로 별도 트랙.

## 배치 순서 제안

M2(활동 허브 골격, 최저위험) → M1(프로필 분리) → M3(오늘 서브탭 MVP) → M5(스트릭 헤더) → M6(팔로우 필터 스위치) → (별도 트랙) M4.

M2를 가장 먼저 두는 이유: 가장 리스크가 낮고(순수 재배치) 나머지 배치들이 그 위에 쌓이는 구조라, 먼저 끝내두면 이후 배치들의 리뷰 범위가 좁아짐.

## 미결 항목 (구현 시작 전 확인 필요)

1. **활동 탭 진입 시 기본 서브탭이 "오늘"인지 "운동 목록"인지.** Record 완료 후 `selectedTab = .activity`로 돌아가는 기존 흐름(`RootTabView.swift:108`)이 있어서, 이 경우엔 "운동 목록"이 자연스러울 수 있지만 평소 탭 진입 시엔 "오늘"이 자연스러울 수 있음 — 진입 경로에 따라 다르게 갈지, 하나로 고정할지 결정 필요.
2. **M1의 새 파일 이름**(`AccountSettingsView.swift` 가칭) 확정.
3. **"오늘" 서브탭과 활동 탭 자체의 라벨 문구**(세그먼트 컨트롤에 뭐라고 쓸지 — "오늘/운동 목록"인지 "Progress/Workouts"인지 등, 톤 확인 필요).
