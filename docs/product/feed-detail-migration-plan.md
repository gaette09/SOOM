# Feed 상세 (2) — 통합 가능성 및 규모 파악

`feed-detail-pdf-spec.md`(목표) + `feed-detail-diff.md`(현재 격차)를 바탕으로, "Feed 상세 하나를 모든 운동 상세 화면의 공통 기반으로 만들 수 있는가"를 판단한다. **코드는 아직 안 건드림 — 이 문서도 조사 결과다.**

## 진행 상황 (2026-08-21 기준)

**정책 확정** (착수 전): 본인 글=Activity 상세와 동일한 전체 깊이, 남의 글=Q1 sanitize 유지 — 뷰는 통합하되 데이터 접근은 절대 통합 안 함. 직접 기록 워크아웃에서 Power/HR Zones/Cadence는 숨기지 않고 대체 콘텐츠로.

**Phase A(뷰 레이아웃 확장) 배치 1~5 완료:**
- **배치 1** — `WorkoutDeepDetailView.swift` 신설(순수 컨테이너, `WorkoutDetailView` 1:1 위임). Activity 상세 3개 실 내비게이션 경로(활동 탭 최근 운동/프로필 운동 기록/AI코치 상세) 전부 이걸로 교체. `ProcessedWorkout`에 `averagePowerWatts`/`averagePowerText` 필드 추가(당장은 항상 nil, forward-compatible). 시각적으로 기존과 완전 동일함을 스크린샷으로 확인.
- **배치 2** — 통계 그리드 4→6칸(PDF와 필드/배치 정확히 일치: 거리/상승고도/시간/평균파워/페이스or속도/칼로리). 회복영향 슬롯은 하단 `WorkoutRecoveryImpactCard`와 중복이라 제거. `WorkoutInsightCueCard` 신설 — `ActivityDetailRhythmCard`/`TerrainInsightCue`를 레이아웃만 공통화(한글 라벨 유지).
- **배치 3** — `WorkoutDistanceChartCard` 신설(거리축 영역차트 공유 셸). Power/Cadence는 소스 무관 항상 placeholder(SOOM에 데이터 소스 자체가 없음). Speed/Elevation은 `WorkoutChartDataBuilder`에 거리 버킷 빌더 추가해 실제로 그림 — 단 `.soomLocal`(Record 직접기록)은 Elevation도 항상 placeholder(Record가 GPS 고도를 안 찍음, HealthKit/GPX/FIT/TCX 임포트만 가능). `ProcessedWorkoutMetric`에 `.speedSeries`/`.elevationSeries` 신설(집계치와 별개 개념).
- **배치 4** — Heart Rate 거리축 차트. `.heartRateSeries`는 비동기 HealthKit 스트림이 필요해 builder가 못 판정 → 호출부가 스트림 resolve 후 `hasHeartRateSeries: Bool`을 builder에 넘기는 구조로 metricAvailability 일관성 유지. HR 전용 Athlete Intelligence 카드 추가(평균/최고 심박 문구) — Elevation용은 스킵(이미 `TerrainInsightCue`가 같은 역할).
- **배치 5** — 스탯 리스트: HR(평균/최고), Speed(평균/최고/이동시간/경과시간), Elevation(상승고도/최고고도)만 추가 — Power/Cadence는 위와 같은 이유로 스킵. Max Speed/Max Elevation은 거리축 차트가 이미 계산한 버킷 샘플의 최댓값 재사용(새 데이터 소스 없음, 200m 버킷 평균이라 순간 최고치보다 약간 낮을 수 있음 — 라벨은 그냥 "최고 속도"로 표기하기로 확정).

검증: 매 배치마다 시뮬레이터 실행 검증 + 임시 override 훅으로 실데이터 렌더 확인 후 완전 제거(`scripts/dev/check-temp-debug-code.sh`로 최종 확인). 빌드는 `scripts/dev/verify-and-check.sh`.

**Phase A 남은 항목(배치 6~) 재평가는 "## 남은 배치 재평가" 섹션 참고 — 원래 순서(6=Power Curve)를 그대로 따르지 않는 게 맞다는 결론.**

**Relative Effort 배치 완료 (2026-08-22)** — 재평가에서 1순위로 재배치한 항목, 예상대로 가장 buildable했음:
- `RelativeEffortComparison`/`RelativeEffortComparisonBuilder` 신설 — "오늘 vs 최근 3주 평균" 비교, ±15% 밴딩(higher/average/lower), 최소 2개 이력 없으면 nil(카드 자체를 숨김).
- `RecoveryCalculator.calculateSummary`(전체 앱 회복 점수, 최근 3일 부하 합산)는 재사용 안 함 — 워크아웃 하나 vs 이력 비교라는 다른 개념. 대신 이미 존재하던 `estimateRelativeEffort(for:)`(3개 매퍼에 동일 공식) 재사용.
- **핵심 발견**: `comparisonWorkouts`/`similarCandidateProvider`(기존 성장 비교 메커니즘)가 내비게이션 경로에 따라 있다 없다 함 — `RootTabView`의 "활동 탭 최근 운동" 경로는 둘 다 안 넘겨서 `.growth` 섹션이 조용히 비어 있었음(기존 버그, `SOOM_KNOWN_ISSUES.md`의 "Growth-Comparison Sections Silently Empty..." 항목 참고, 이번 배치에서 발견만 하고 안 고침). 이 위에 얹으면 Relative Effort도 반쪽짜리가 되므로, `RelativeEffortHistoryProviding`(새 프로토콜, `WorkoutDetailRouteContextProviding`과 동일 DI 컨벤션)이라는 독립 데이터 경로를 새로 만들어서 `RootTabView`/`UnifiedWorkoutLibraryViewContainer` 두 실 진입점 모두에 명시적으로 배선.
- `RelativeEffortCard` — PDF의 3단 컬러바(higher=주황/average=보라/lower=파랑, 워크아웃 tint 아님 — 3개 상태가 실제 의미를 가지므로), `.recovery` 섹션 최상단(`WorkoutRecoveryImpactCard` 바로 위)에 배치.
- 시뮬레이터 검증: `relativeEffortComparisonOverride` 임시 훅으로 3단계 전부 확인(접근성 트리 텍스트 정확히 일치), 완료 후 제거.

**배치 7(지도 성취 마커) 완료 (2026-08-22)** — 파워 제외, 페이스/속도만, "Lifetime" 대신 "최근 N개월"(상수화):
- `WorkoutSegmentBestEffortFinder` 신설 — route에서 1분/5분/10분 rolling-window 최고 페이스/속도 추출(투 포인터, O(n)). `.soomLocal`도 타임스탬프는 있어서 동작함(파워/케이던스와 달리 안 막힘).
- `WorkoutAchievementConfig` — `lookbackMonths = 3`, `minimumHistoryCount = 2`, `topRankThreshold = 3`, `maximumMarkers = 2`. 전부 이 파일 하나만 바꾸면 조정됨.
- `WorkoutAchievementHistoryProviding`/`SwiftDataWorkoutAchievementHistoryProvider` — Relative Effort와 동일하게 `comparisonWorkouts`/`similarCandidateProvider`와 무관한 독립 경로. `WorkoutRoutePersistenceStoring.fetchRoutes(workoutIds:)` 배치 조회 API를 활용해 최근 N개월치 route를 한 번에 가져옴(개별 워크아웃마다 비동기 호출 안 함 — 처음 걱정했던 성능 이슈가 기존 API로 이미 해결돼 있었음).
- **핵심 발견 — 지도가 두 가지 렌더링 경로로 나뉘어 있었음**: route가 있는 워크아웃은 `WorkoutMapSheetScaffold`(전체 화면 지도 시트) 경로를, route가 없으면 `ActivityDetailHeroMap`(정적 히어로 배너) 경로를 탄다. 둘 다 내부적으로는 같은 `SOOMMapboxRouteMap`(Mapbox)을 쓰고 있어서, achievements 파라미터 하나를 그 공용 컴포넌트에 추가하고 양쪽 호출 체인에 배선하는 것으로 해결 — 처음엔 MapKit도 관여하는 줄 알았으나(`WorkoutMapSheetScaffold`가 `import MapKit`) 그건 카메라 상태 타입(`MapCameraPosition`)용일 뿐, 실제 렌더링은 전부 Mapbox였음.
- 마커 이미지는 `UIGraphicsImageRenderer`로 흰 원+tint 테두리+`SOOMIcon.medal`(SF Symbol, 새 에셋 불필요) 조합해서 직접 생성 — `PointAnnotation.Image(image:name:)`.
- `WorkoutAchievementCard` — 지도 아래 배너, 순위별 카피(1위="꾸준히 쌓아온 리듬이 만든 결과예요", 2/3위="좋은 흐름이 이어지고 있다는 신호예요") 사용자 톤 확인 완료.
- 시뮬레이터 검증: `detailRouteOverride`+`achievementsOverride` 임시 훅으로 마커 2개(1위/2위) 지도 렌더 + 배너 카피 정확히 일치 확인, 완료 후 제거.

**배치 8(동승자 태깅) 완료 (2026-08-22)** — 팔로우 그래프(blocked_by 걸려있는 그 기능)와 무관하게 독립적으로 진행 가능하다는 재평가가 맞았음, 순수 자유 텍스트로 구현:

- `WorkoutCompanionNameEditing`(순수 함수 모음) — `profiles`/`follows` 조회 없이 로컬 포맷팅만: 트림, 최대 20자, 대소문자 무시 중복 제거, 최대 10명 캡. 사람 식별(누구인지) 자체가 목표가 아니라 "누구와 뛰었는지 기억"만 목표라 신원 매칭 없이도 실효성 있다고 판단.
- `WorkoutCompanionUpdateService` → `UnifiedWorkoutStore.updateCompanions(id:names:)` 경유해 SwiftData에 영속화. `WorkoutCompanionCard`(표시, 소스 태그+동승자 태그 함께 `FlowTags`로 렌더)와 `WorkoutCompanionEditSheet`(추가/삭제 UI, 칩 형태) 분리.
- **접근성 주의사항 발견**: `WorkoutCompanionCard`가 `.accessibilityElement(children: .contain)` + 명시적 `.accessibilityLabel("태그")`/`.accessibilityValue(...)`를 컨테이너에 걸어두면, 내부 `Button(action: onTapEdit)`가 상세 화면의 바깥쪽 AX 트리 스캔에서 별도 인덱스 요소로 잡히지 않음(컨테이너 자체의 요약된 Value만 노출됨) — 반면 `WorkoutCompanionEditSheet` 내부의 삭제 칩 버튼은 인덱스로 정상 탐색됨. 이 카드류를 다룰 때는 element-index 클릭보다 좌표 클릭이 필요할 수 있다는 점 기억해둘 것.
- 검증 #1(SwiftData 백업 실 `UnifiedWorkout`, 새 격리 시뮬레이터 `SOOM-Verify`에서 진행 — 사용자가 다른 세션에서 쓰던 기존 시뮬레이터는 건드리지 않음): 동승자 추가 → 저장 → 태그 카드에 반영 확인 → 편집 시트 재진입 → 삭제 → 저장 → 태그 카드에서 제거 확인 → 앱 완전 종료 후 재실행(cold relaunch, 백그라운드 전환 아님) → 삭제 상태가 영속됨을 재확인. 임시 시드 훅(`// TEMP batch-8 verification, remove after`)은 검증 완료 후 제거, `check-temp-debug-code.sh` 클린 확인, `verify-and-check.sh` 빌드 성공 확인.
- 검증 #2(레거시 mock `Workout` 경로, 이전 세션에서 확인): 크래시 없이 동일하게 동작.
- `WorkoutCompanionNameEditingTests.swift` — 정규화/추가/삭제/중복제거/최대개수 전부 유닛 테스트로 커버.

**배치 9(Fitness Increased) 완료 (2026-08-22)** — 정통 CTL(Chronic Training Load) 모델로 구현(사용자 판단: 단순화 버전 대신 Strava/TrainingPeaks와 동일한 42일 지수가중이동평균 방식 선택):

- `FitnessTrendCalculator.chronicLoadSeries(dailyLoads:)` — 일별 부하 버킷(운동 없는 날=0)에 대해 `CTL[d] = CTL[d-1] + (load[d] - CTL[d-1]) / 42` 재귀식 적용, 콜드스타트는 0에서 시작(과거 앱 사용 이력이 없는 기간의 "체력"을 가정하지 않음 — `estimateTrainingLoad`의 "MVP 추정치" TODO와 같은 정신).
- **재사용 발견**: 이미 `RecoveryCalculator`가 3일 회복 점수 계산에 쓰던 per-workout `trainingLoad` 추정치(`HealthKitRecoveryActivityMapper`/`ProcessedWorkoutToRecoveryActivityMapper`/`UnifiedWorkoutToRecoveryActivityMapper` 3곳에 동일 공식)가 CTL의 원재료로 그대로 재사용 가능했음 — 새 부하 공식을 발명할 필요 없이 "누적 윈도우만 42일로 확장"하면 됐음. 원 계획 문서의 "새 도메인 모델 필요" 평가는 부분적으로만 맞았던 셈(누적 로직은 새로 필요했지만 부하 자체는 기존 값 재사용).
- `FitnessTrendHistoryProviding`/`SwiftDataFitnessTrendHistoryProvider` — Relative Effort/Achievements와 동일 독립 DI 패턴. 캘린더 일 단위로 같은 날 여러 운동의 부하를 합산하고 휴식일은 0으로 채워 넣는 버킷팅 담당.
- `FitnessTrendBuilder` — 수렴 여유를 위해 `recommendedHistoryWindowDays = 126`(42일의 3배, 95%+ 수렴) 만큼 이력을 가져오되, 실제 운동일이 2일 미만이면 카드 자체를 숨김(Relative Effort와 동일한 "hide, don't mislead" 컨벤션, `minimumTrainingDayCount` 재사용 값 아님 — 별도 상수지만 같은 임계값 2 채택).
- "Points +3" = 오늘 CTL − 어제 CTL(정수 반올림 후 차이) — 이 워크아웃이 기여한 체력 점수 증가분. "Fitness Score 35" = 오늘 CTL 반올림.
- `FitnessTrendCard` — PDF의 좌측 라벨/값 2쌍("포인트"/"체력 점수")+우측 미니 스파크라인 레이아웃. 스파크라인은 `TrendCard.MiniTrendLine`과 동일한 normalize+Path+stroke 패턴을 재사용하지 않고 별도 `private struct MiniSparkline`으로 새로 작성(기존 것이 `TrendCard.swift` 내부 `private`이라 외부에서 재사용 불가 — 2회 반복 수준이라 별도 공유 컴포넌트로 추출하지는 않음). PDF의 "View your Fitness trend" 링크는 **의도적으로 생략** — 대상 화면(집계 Fitness 트렌드 screen)이 아직 없고 이번 배치 범위 밖("View X" 링크는 원 배치 재평가 문서의 컨벤션대로 대상 화면을 실제로 만드는 배치에 묶어 처리).
- `.recovery` 섹션에서 `RelativeEffortCard` 바로 위(PDF 순서: Fitness Increased(10번)가 Relative Effort(11번)보다 앞)에 배치.
- 두 실 진입점(`RootTabView`의 `.directWorkout` 경로, `UnifiedWorkoutLibraryViewContainer`) 모두에 `fitnessTrendHistoryProvider` 명시적 배선.
- 유닛 테스트 12개(`FitnessTrendCalculatorTests`/`FitnessTrendBuilderTests`/`FitnessTrendHistoryProviderTests`) — CTL 재귀식 수렴/감쇠, 최소 이력 게이트, 부하 버킷팅(동일 날짜 합산/제외 필터/윈도우 밖 제외) 커버. 격리된 `SOOM-Verify` 시뮬레이터(사용자가 다른 세션에서 쓰던 기존 시뮬레이터는 건드리지 않음)에서 전부 통과 확인.
- 시뮬레이터 UI 검증: 임시 시드 훅으로 서로 다른 6일(10/7/5/3/1/0일 전)에 걸친 SwiftData `UnifiedWorkout` 시드 후 실행 → 운동 상세 화면에서 접근성 트리 텍스트로 "체력 향상 체력 점수 15, 어제보다 3 상승"이 `.recovery` 섹션 최상단(운동 강도 카드 바로 위)에 정확히 렌더링됨을 확인 — PDF 순서, 라벨, 계산값 전부 기대대로. 검증 후 임시 시드 훅 제거, `check-temp-debug-code.sh` 클린 확인, `verify-and-check.sh` 빌드 성공 재확인.

## 먼저 확인해야 하는, 규모보다 앞서는 질문 하나

**Activity 상세는 항상 "내 워크아웃"만 보여주고, Feed 상세는 "내 것 + 남의 것"을 둘 다 보여줄 수 있다.** `UnifiedWorkoutDetailDestination`/`ActivityView`는 전부 `SwiftDataUnifiedWorkoutStore`(로컬 기기 데이터)만 조회 — 항상 이 기기 소유자의 워크아웃이다. 반면 Feed는 Supabase에서 팔로워/공개 게시물을 가져오므로(`SupabaseFeedRepository`), `FeedItemDetailView`가 받는 `FeedItem`은 **다른 사람이 쓴 것일 수 있다.**

이게 왜 규모 파악보다 먼저인가: PDF 스펙 그대로(Power Zones, HR Zones, Cadence, 실 SwiftData 기반 차트 등)를 "공통 컴포넌트 하나"로 만들어서 Feed 상세에도 그대로 꽂으면, **그 컴포넌트가 원본 데이터를 다시 조회하는 구조일 경우 남의 비공개 훈련 데이터에 접근하게 된다** — Q1에서 `FeedItemDetailView`에 명시적으로 박아둔 불변식("절대 원본 데이터로 되돌아가지 않는다")과 정면 충돌. 따라서:

- **"하나의 뷰가 항상 원본을 다시 조회"하는 방식의 통합은 불가능** — Feed 컨텍스트에서 안전하지 않음.
- **"하나의 뷰 레이아웃 + 두 개의 서로 다른 데이터 어댑터"는 가능** — Activity 어댑터는 실 SwiftData/HealthKit에서, Feed 어댑터는 `FeedItem`/`ShareableWorkoutCardModel`(이미 sanitize된 것)에서 같은 모양의 프레젠테이션 모델을 만들어 같은 뷰에 공급.

**이 판단을 사용자가 먼저 확정해줘야 함**: Feed 상세에서 "내가 올린 내 글"을 볼 때와 "남이 올린 글"을 볼 때 보여줄 수 있는 깊이가 같아야 하는지(둘 다 sanitize된 만큼만), 아니면 "내 글은 나만 볼 때 더 깊게"(예: 본인 워크아웃이면 Feed 상세에서도 Activity 수준 전체를 보여주는) 허용할지. PDF 원본은 이 구분 자체가 없음(1인용 앱 시연이라 전부 "내 활동"). 이 판단에 따라 아래 규모가 꽤 달라진다.

## 통합 가능성 결론

**뷰(레이아웃) 레벨 통합은 가능하고 바람직함. 데이터 접근 레벨 통합은 하면 안 됨.**

구체적으로:
1. PDF의 21블록을 표현하는 **프레젠테이션 모델**(대부분 옵셔널 필드 — 있으면 그 섹션 표시, 없으면 숨김. `ActivityDetailVisibilityPolicy`가 이미 이 패턴을 쓰고 있어 새로운 개념 아님) 하나를 새로 설계.
2. 이 모델을 렌더링하는 **새 SwiftUI 뷰 컴포넌트 세트**(지도 위 성취마커, 거리축 영역차트+회색 오버레이, Athlete Intelligence 반복 카드, Relative Effort 3단바, Results 2×2, Power Curve 로그축 등)를 신규로 만듦 — 이건 현재 `FeedItemDetailView`에도 `WorkoutDetailContent`에도 없는 컴포넌트라 **어느 쪽이든 처음부터 새로 짜야 함**.
3. **어댑터 2개**를 별도로 만듦:
   - Activity 어댑터: `UnifiedWorkout` + 실 SwiftData/HealthKit → 프레젠테이션 모델 (기존 `WorkoutChartDataBuilder`/zone provider 등 재사용 가능)
   - Feed 어댑터: `FeedItem`/`ShareableWorkoutCardModel` → 같은 프레젠테이션 모델 (sanitize된 필드만, 원본 재조회 없음 — Q1 불변식 유지)

## 규모 파악 — 무엇이 신규이고 무엇이 재사용 가능한가

### 완전 신규 (양쪽 어디에도 없음)
- 지도 위 성취 마커(핀)
- 경로 영상 리플레이 CTA
- 동승자 태깅
- Fitness Increased 카드
- Relative Effort 3단 비교바(주간, PDF 형태 그대로는)
- Results(Segments/Achievements/Challenges 카운트) — **이건 SOOM에 "Segments"/"Challenges 참여 카운트" 개념 자체가 없어서 카드 UI보다 그 앞의 도메인 모델부터 없음**
- Workout Analysis 막대+삼각형 차트
- Power Curve(로그축) 차트
- 거리축 영역차트 컴포넌트(Power/HR/Speed/Cadence/Elevation 5개가 사실상 같은 컴포넌트의 색만 다른 재사용 — 컴포넌트 자체는 1개 신규)
- 섹션별 반복 Athlete Intelligence 카드(일반화된 형태로는 신규 — Activity의 `WorkoutSessionSummaryCard`/`ActivityDetailRhythmCard`가 컨셉은 있으나 "섹션마다 다른 문구" 패턴은 아님)
- "View X" → 별도 화면 연결 링크 다수(Power Curve 상세, All Results 등 — 그 "별도 화면"들 자체가 대부분 없음)

### 이미 있어서 재사용 가능
- Zone 분포 막대(Z1~Z7, %+범위) — `WorkoutZoneSection`/`WorkoutZoneDataProvider`(HealthKit 소스에서 이미 실데이터로 동작, Q2/Q4에서 확인된 제약과 동일하게 유지됨)
- 페이스/스플릿 원본 데이터 파이프라인 — `WorkoutChartDataBuilder`(Q2), 단 축을 분→거리로 바꾸는 작업 필요
- AI 서술형 카드 개념 — `WorkoutSessionSummaryCard`/`ActivityDetailRhythmCard`(문구 생성 로직 재사용 가능, 배치/반복 패턴만 새로 설계)
- "집계 Training Zones" 화면(기간 필터+Zone 분포) — SOOM에 정확히 대응하는 화면은 없지만 데이터 소스(zone provider)는 이미 있음
- 통계 그리드 렌더링 패턴(`ActivityDetailStatTile`/`FeedReferenceMetricGrid`) — 필드 개수/구성만 늘리면 됨

### 구조적으로 막혀서 PDF 그대로는 불가능한 것
- **Power/HR Zones, Cadence, 파워 관련 전부** — `.soomLocal`(직접 기록) 워크아웃엔 심박·파워·케이던스 원천 데이터가 없음(Q2에서 이미 확정: Record가 GPS만 캡처). HealthKit 소스가 아니면 이 섹션들은 SOOM에서 영구히 빈 상태일 수밖에 없음 — PDF를 "완전히 동일하게" 만드는 목표와 정면으로 부딪히는 지점. **직접 기록 워크아웃에 대해서는 이 섹션들을 어떻게 처리할지(숨김 vs 다른 대체 콘텐츠) 사용자 판단이 필요.**
- **Results의 Segments/Challenges** — Strava 고유의 "구간 기록 경쟁"/"챌린지 참여" 도메인 개념이 SOOM엔 없음. Challenge는 Club 쪽에 있지만 개별 워크아웃과 연결된 구조가 아님.

## 배치 규모 감(코드 수정 없이 감만 — 실제 계획은 위 정책 질문이 확정된 뒤 다시 짜야 함)

이건 지금까지 진행한 IA 마이그레이션(M1~M6, 각 배치가 파일 1~3개 수준)과 **완전히 다른 체급**이다. 대략적인 감:

- 프레젠테이션 모델 설계 + Activity 어댑터: 중간~큰 배치 1~2개
- 신규 UI 컴포넌트(거리축 차트, Athlete Intelligence 반복 카드, Relative Effort, Results, Fitness Increased): 각각 별도 배치급, 합치면 5~8개 배치
- 지도 위 성취마커 + 경로 영상 리플레이: Mapbox 통합 지식이 필요한 별도 배치(영상 생성은 특히 큰 미지수 — 인코딩/렌더링 파이프라인이 SOOM에 전무)
- 동승자 태깅: 팔로우 그래프(현재 blocked_by 걸려있는 그 기능)와 사실상 같이 가야 실효성 있음 — 독립적으로 작게 뗄 수 없을 가능성
- Feed 어댑터 + 프라이버시 경계 재설계: 위에서 언급한 정책 결정이 선행돼야 시작 가능

**총 배치 수 추정: 대략 12~18개.** 지금까지의 IA 마이그레이션 전체(M1~M6, 6개)보다 이 작업 하나가 2~3배 큼 — "제일 정밀하게 봐야 한다"는 우선순위 지정이 실제 작업량과 맞아떨어짐.

## 다음 단계 제안

코드를 시작하기 전에 아래 순서로 확정이 필요:

1. **위 "먼저 확인해야 하는 질문"** — 본인 글 vs 남의 글 Feed 상세 깊이 차등 여부.
2. **HealthKit 전용 섹션(Zone/Power/Cadence) 처리 방향** — 직접 기록 워크아웃에서 숨길지, 대체 콘텐츠를 넣을지.
3. 위 두 개가 정해지면, 프레젠테이션 모델의 정확한 필드 목록을 확정하고 첫 배치(모델 설계 + Activity 어댑터, 신규 UI 없이 기존 컴포넌트 재배치만)부터 시작하는 게 리스크가 가장 낮은 순서로 보임 — 다만 이건 지금 시점의 감이고, 위 두 정책 질문 답변에 따라 순서 자체가 바뀔 수 있음.

## 남은 배치 재평가 (2026-08-21, Phase A 배치 1~5 완료 후)

원래 "완전 신규" 목록(위 27번째 줄)에 순서 없이 나열돼 있던 항목들을, 배치 1~5를 실제로 만들면서 확인된 SOOM의 진짜 데이터 가용성 기준으로 다시 정렬한다. **결론부터: "배치 6 = Power Curve"로 그냥 이어가면 안 된다.** Power Curve는 Results/영상 리플레이와 같은 급으로 막혀 있다는 게 이번에 새로 확인됐다.

### 재분류의 핵심 발견 — Power Curve/Workout Analysis는 Power 카드와 똑같이 막혀 있다

배치 3에서 이미 확정한 사실: SOOM엔 파워 데이터 소스가 소스 불문 전무하다(`.soomLocal`은 물론 HealthKit 임포트도 — `UnifiedWorkout`에 파워 필드 자체가 없음, batch1의 `averagePowerWatts` doc-comment 참고). 그런데 PDF의 **Power Curve(14번, 로그축 시간)**도, **Workout Analysis(13번, 파워 구간별 막대+삼각형)**도 전부 파워 시계열이 원재료다. 즉 이 둘은 "새 차트 컴포넌트를 만들면 되는" 문제가 아니라 Power 카드(배치3)와 완전히 같은 이유로 100% placeholder일 수밖에 없다 — 데이터가 생기기 전까진 셸만 만들어봐야 배치3의 Power/Cadence placeholder를 두 번 더 반복하는 것과 다르지 않다. **Results/영상 리플레이와 같은 최하위 티어로 재분류.**

### 반대로, 예상보다 훨씬 덜 막힌 항목 — Relative Effort

PDF의 Relative Effort(11번)는 "오늘 운동점수 + 최근 3주 평균 대비 비교" 3단 바다. 코드를 확인해보니 SOOM에 이미:
- **`estimateRelativeEffort(for:)`가 세 곳에 이미 구현돼 있음**(`HealthKitRecoveryActivityMapper.swift:43`, `ProcessedWorkoutToRecoveryActivityMapper.swift:43`, `UnifiedWorkoutToRecoveryActivityMapper.swift:43`) — 지금은 Recovery 파이프라인 내부용으로만 쓰이고 화면에 직접 노출되지 않을 뿐, 워크아웃 단위 숫자 점수가 이미 계산되고 있다.
- **`RecoverySummary`(`RecoveryModels.swift`)가 이미 단일 점수+`trends`+`trendText` 구조** — PDF의 "숫자 하나 + 최근 평균 대비 비교"와 개념이 거의 그대로 겹친다(soom-original-spec.md에서 짚었던 "운동점수 → 회복 자동 설정" SOOM 차별점이 바로 이 자리).

즉 Relative Effort는 새 도메인 모델을 발명할 필요가 거의 없고, 기존 값을 뷰에 노출 + "최근 3주 평균" 집계 로직만 추가하면 되는 수준 — **남은 항목 중 가장 buildable함.**

### 중간 — 부분적으로 덜 막힘, 그래도 새 계산 필요

- **지도 위 성취 마커**: `PersonalRecordBuilder`/`PersonalRecord`(`PersonalRecord.swift`) 도메인 개념이 이미 있지만, **워크아웃 전체 단위** PR(가장 멀리/가장 오래/가장 빠른 평균 등)이지 PDF의 "3분 구간 lifetime best" 같은 **세그먼트(rolling-window) 단위** 개념이 아니다. 기존 개념을 확장은 할 수 있어도 세그먼트 단위 계산 로직은 새로 필요 — 지도 핀 렌더링(Mapbox) 작업도 별도.
- **동승자 태깅**: 외부 파이프라인 의존은 없지만(팔로우 그래프와 무관하게 독립적으로 가능하다는 게 이번에 재확인됨 — SOOM-OS CLAUDE.md의 "Feed 팔로우 그래프 blocked" 항목은 Feed 자체 얘기고 이 태깅 기능과는 별개), "누구와 같이 뛰었나"를 저장/표시하는 새 데이터 모델 + UI가 필요한 순수 신규 기능.
- **Fitness Increased**: fitness-score 트렌드(Strava의 CTL 유사 개념) 자체가 SOOM에 없음 — Relative Effort의 단발성 점수와 달리 시계열 누적이 필요해서 새 도메인 모델 필요.

### 최하위 (원래도 "큰 미지수"였고, 지금도 그대로 맞음 + Power Curve/Workout Analysis 합류)

- **Results**(Segments/Achievements/Challenges) — 도메인 모델 자체가 없음.
- **경로 영상 리플레이** — 인코딩/렌더링 파이프라인 전무, 가장 큰 미지수.
- **Power Curve / Workout Analysis** — 위에서 재분류한 대로, 파워 데이터 소스가 생기기 전까진 착수 실익이 없음.

### "View X" 링크

독립 배치가 아님 — 각 링크는 그 섹션의 "더 깊은 버전" 화면으로 연결되는데, 그 타겟 화면들(집계 Power/HR Zones, All Results, Fitness 트렌드 등) 자체가 아직 없다. 해당 섹션을 실제로 만드는 배치에 묶어서 같이 처리(예: Relative Effort 배치에서 "View Weekly Effort" 링크도 같이 판단).

### 다음 세션 시작점 — 권장 순서

1. ~~Relative Effort~~ — 완료 (2026-08-22, 위 참고).
2. ~~지도 위 성취 마커~~ — 배치 7 완료 (2026-08-22, 위 참고).
3. ~~동승자 태깅~~ — 배치 8 완료 (2026-08-22, 위 참고).
4. ~~Fitness Increased~~ — 배치 9 완료 (2026-08-22, 위 참고).
5. **다음 후보** — Results / 경로 영상 리플레이 / Power Curve / Workout Analysis, 전부 최하위 티어(파워 데이터 소스나 도메인 모델처럼 이 마이그레이션 범위를 넘어서는 선행 작업이 생기기 전까진 보류). Phase A의 "완전 신규" 목록 중 남은 buildable 항목은 사실상 소진됨 — 다음 세션은 여기서 더 파거나(예: Results의 최소 도메인 모델 범위 재검토), Phase B(본인/남의 글 Feed 어댑터)로 전환하는 것 중 사용자 판단 필요.
6. Phase B(본인/남의 글 분기, Feed 어댑터, `FeedItemDetailView` 교체) — Phase A 항목들과 독립적으로 아무 때나 시작 가능(정책은 이미 확정됨), 위 순서와 병행 검토 가능
