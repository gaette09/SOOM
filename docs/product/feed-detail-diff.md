# Feed 상세 (2) — PDF vs 현재 구현 필드 단위 Diff

`feed-detail-pdf-spec.md`의 21블록을 기준으로, SOOM에 이미 있는 **두 개의 서로 다른** "상세" 화면과 대조한다:

- **Feed 상세** = `SOOM/Features/Feed/FeedItemDetailView.swift` (Q1에서 신규 작성, `FeedView.swift`의 `feedDestination(for:)`가 연결)
- **Activity 상세** = `SOOM/Features/Activity/WorkoutDetailContent.swift` + `UnifiedWorkoutDetailDestination`(`UnifiedWorkoutLibraryView.swift`) — 활동 탭 최근 운동(Q4가 연결), 프로필 운동 기록, 활동 AI코치 안 상세가 전부 궁극적으로 이 화면으로 연결됨(직접 `WorkoutDetailView` 또는 `UnifiedWorkoutDetailDestination` 경유)

범례: ✅ 있음(구조 일치) · 🟡 부분적으로 있음(다른 데이터/다른 형태) · ❌ 없음

## 핵심 요약 먼저

**Feed 상세와 Activity 상세는 서로 완전히 다른 설계 철학으로 만들어졌다.** Feed 상세(Q1)는 의도적으로 얕음 — `ShareCardPrivacyPolicy`로 이미 sanitize된 `FeedItem`/`ShareableWorkoutCardModel` 필드만 읽고, 원본 데이터로 절대 되돌아가지 않는다는 불변식이 파일 상단 주석에 명시돼 있음. Activity 상세(Q2까지 거쳐서)는 실제 SwiftData 원본 데이터에 직접 접근해서 실 페이스/스플릿 차트, Zone 분석, AI 서술형 카드를 이미 갖추고 있어 **PDF 스펙에 구조적으로 훨씬 더 가깝다.** 그런데 Activity 상세도 PDF가 요구하는 깊이(Power/HR/Speed/Cadence/Elevation 개별 카드, Relative Effort, Results, Fitness Increased, 지도 위 성취 마커, 동승자 태깅, 경로 영상)에는 한참 못 미친다.

## 블록별 대조표

| # | PDF 블록 | Feed 상세 (FeedItemDetailView) | Activity 상세 (WorkoutDetailContent) |
|---|---|---|---|
| 1 | 헤더 지도(경로+캐러셀+성취마커+영상재생) | 🟡 `FeedReferenceMediaPreview` — 정적 지도/사진만, 캐러셀·성취마커·영상재생 없음 | 🟡 `ActivityDetailHeroMap`/`WorkoutMapSheetScaffold` — 실 지도(Mapbox)는 있으나 성취마커·영상재생·캐러셀 없음 |
| 2 | 작성자/날짜(절대시각)/종목 | 🟡 아바타+이름+상대시간(`relativeTimeText`) — **절대시각 아님**, 종목은 별도 칩(`feedTypeText`) | ✅ `DetailHeader`에 종목/제목/거리·시간 서브타이틀, 단 "종목만 다르고 절대시각 표기 관례 SOOM 전역과 동일(추가 확인 필요 없음, 기존 패턴 따름)" |
| 3 | 제목 | ✅ `feedTitle` | ✅ `workout.title` |
| 4 | 구조화 본문(이모지 2블록) | ❌ 없음 — `caption`/`optionalShortStory`/`emotionalContext` 순 자유 텍스트 1개만, 이모지 구조화 라인 없음 | 🟡 `WorkoutSessionSummaryCard`가 AI 서술형 요약을 보여주지만 PDF처럼 이모지 태그 붙은 다중 라인 구조는 아님 |
| 5 | 성취 배너 | ❌ 없음 | ❌ 없음(Activity에 "achievements" 개념 자체가 없음) |
| 6 | 통계 그리드 2×3(6칸: Distance/ElevGain/MovingTime/AvgPower/AvgSpeed/Calories) | 🟡 `FeedReferenceMetricGrid`, 기본 4칸(거리/시간/페이스or속도/획득고도) + 심박·활동에너지 데이터가 있으면 최대 6칸까지 늘어남(`workoutMetrics(for:)`, `FeedItemDetailView.swift:124-138`) — 필드 구성은 다르지만 칸 수는 데이터에 따라 PDF와 같아질 수 있음, 레이아웃은 1행 나열(LazyVGrid 아님)이라 2×3 그리드는 아님 | 🟡 `ActivityDetailSummaryMetrics.metrics(processedWorkout:recoveryImpact:)`(`WorkoutDetailContent.swift:1255-1266`) — 정확히 **4칸 고정**(거리/시간/페이스or속도/회복영향 또는 평균심박), 2×2 그리드. PDF의 6칸에는 둘 다 못 미침, Elevation Gain·Calories는 SOOM 어느 쪽에도 이 그리드엔 없음 |
| 7 | Athlete Intelligence(종합) | 🟡 `messageBlock`이 `primaryMessage`/`growthMessage`/`recoveryMessage` 3줄을 보여주지만 "Say More" 확장 버튼 없음, 문구가 AI 서술형이 아니라 사전 정의된 짧은 문장 | ✅ `WorkoutSessionSummaryCard` + `ActivityDetailRhythmCard`가 실제 AI 서술형 카드 — PDF의 "Athlete Intelligence" 개념과 가장 가까운 기존 컴포넌트 |
| 8 | 동승자 태그 | ❌ 없음 | ❌ 없음(SOOM에 "같이 운동한 사람 태그" 기능 자체가 없음, Q1 조사 때도 확인) |
| 9 | 좋아요/댓글/공유 액션바 | ❌ **`FeedItemDetailView.swift` 재정독으로 확정 — 액션바 자체가 없음.** `FeedItemCard`(피드 목록 카드)엔 응원/댓글/저장 3버튼이 있지만 전부 `Button(action: {})` 미연결이고, 그마저도 상세 화면(`FeedItemDetailView`)엔 아예 옮겨오지 않았음 — 목록 카드에서 눌러도 아무 반응 없는 그 버튼들이 상세에는 존재하지도 않는 상태 | ❌ 좋아요/댓글/공유 개념 자체가 Activity 상세엔 없음(공유는 별도 "공유하기" 플로우로 존재, 이 화면 인라인 액션바 아님) |
| 10 | Fitness Increased | ❌ 없음 | ❌ 없음 |
| 11 | Relative Effort(주간 비교) | ❌ 없음 | 🟡 개념적으로 SOOM의 Recovery 점수(`RecoverySummary`, 단일 점수)와 가장 가깝지만 이 화면에 직접 표시되진 않음, `WorkoutRecoveryImpactCard`가 근접 |
| 12 | Results(PowerSkills/Segments/Achievements/Challenges) | ❌ 없음 | ❌ 없음(Segments/Challenges 카운트 개념 자체가 SOOM에 없음) |
| 13 | Workout Analysis(막대+삼각형 차트) | ❌ 없음 | ❌ 없음(이런 형태의 차트 없음) |
| 14 | Power Curve(로그스케일 시간축) | ❌ 없음 | ❌ 없음 |
| 15 | Power(거리축 영역차트+6개 통계) | ❌ 없음 | 🟡 파워 데이터 자체는 `ShareableWorkoutCardModel`에 있지만(Q2에서 `WorkoutSample.power` optional 추가) 이 정도 통계 세트·차트는 없음 |
| 16 | Power Zones | ❌ 없음 | 🟡 `WorkoutZoneSection`이 존재하지만 **HealthKit 소스일 때만**(zoneDataProvider) 실데이터, `.soomLocal`은 항상 비어있음(Q2/Q4에서 이미 확인된 구조적 한계) |
| 17 | Heart Rate(거리축 영역차트) | ❌ 없음 | 🟡 `WorkoutChartStack.heartRateChart`가 있지만 **LineMark(선 그래프), X축이 분(시간) 기준** — PDF는 영역(area fill)+회색 비교 오버레이, X축이 km. 데이터도 HealthKit 소스만 실제로 채워짐(Q2) |
| 18 | Heart Rate Zones | ❌ 없음 | 🟡 16번과 동일 상황(`WorkoutZoneSection`, HealthKit 전용) |
| 19 | Speed | ❌ 없음 | 🟡 `WorkoutChartStack.paceChart`가 페이스/속도를 그리지만 형태(LineMark, 분 축)가 PDF와 다름 |
| 20 | Cadence | ❌ 없음 | ❌ 없음(케이던스 차트 없음, 케이던스 데이터 자체가 SOOM 모델에 거의 없음) |
| 21 | Elevation(+ Athlete Intelligence) | ❌ 없음 | ❌ 없음(고도 차트 없음, `elevationGainMeters` 필드는 있지만 시계열 차트 없음) |

## 구조적으로 가장 중요한 발견

1. **차트 축이 근본적으로 다름.** SOOM(`WorkoutChartStack`)은 시간(분) 축 LineMark, PDF는 거리(km) 축 영역차트+회색 비교 오버레이. 이건 "카드 하나 추가"가 아니라 **기존 `WorkoutSample` 모델과 차트 컴포넌트를 거리 축 기반으로 다시 설계**해야 한다는 뜻 — Q2에서 만든 `WorkoutChartDataBuilder`(분 단위 버킷)를 거리 단위 버킷으로 바꾸거나 병행해야 함.
2. **Zone 데이터가 HealthKit 소스에서만 실제로 채워짐**은 Q2/Q4에서 이미 구조적으로 확인·수용된 제약 — PDF를 그대로 복제하려면 이 제약을 다시 마주치게 됨(직접 기록엔 심박이 없으므로 Heart Rate/Power Zones는 여전히 HealthKit 전용일 수밖에 없음).
3. **PDF 고유 개념 중 SOOM에 아예 없는 것**: 지도 위 성취 마커, 경로 영상 리플레이, 동승자 태깅, Fitness Increased, Relative Effort(주간 비교 형태로는), Results(Segments/Achievements/Challenges 카운트), Workout Analysis 막대차트, Power Curve, Cadence 차트. 이 8개는 "필드 보강"이 아니라 **신규 기능**.
4. **Feed 상세는 Activity 상세보다 훨씬 얕다** — 통합 기반으로 삼으려면 Feed 상세를 Activity 상세 수준으로 끌어올리거나, Activity 상세의 실데이터 파이프라인을 Feed로 가져와야 함. 근데 Feed는 Q1의 프라이버시 경계(sanitize된 필드만) 때문에 원본 SwiftData에 접근하면 안 됨 — 이 긴장 관계가 3단계(migration-plan) 문서의 핵심 쟁점.
