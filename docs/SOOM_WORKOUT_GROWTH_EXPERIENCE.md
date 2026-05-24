# SOOM Workout Growth Experience v1

## A. Purpose

Workout Detail은 사용자가 한 번의 운동을 다시 보면서 “무엇을 했는가”뿐 아니라 “어디가 좋아지고 있고, 다음에는 무엇을 개선하면 좋은가”를 이해하는 화면이다.

SOOM의 운동 상세는 Strava처럼 기록성과 성취를 분명히 보여주되, Apple Fitness처럼 정돈된 요약과 읽기 쉬운 흐름을 유지한다. 목표는 복잡한 페이스, 심박, 파워, 스플릿 데이터를 사용자가 성장 신호로 이해하게 만드는 것이다.

장기적으로 Workout Growth Experience는 Apple HealthKit, Garmin, Samsung Health, SOOM 자체 기록을 직접 구분하지 않고 `UnifiedWorkout` 기반으로 확장한다. 통합 데이터 소스 설계 기준은 [SOOM_UNIFIED_HEALTH_DATA_SOURCE.md](SOOM_UNIFIED_HEALTH_DATA_SOURCE.md)를 따른다.

운동 상세의 핵심 목적:

- 운동 결과를 빠르게 이해한다.
- 개인 기록, 이전 운동 대비 개선, 최근 4주 흐름을 통해 성장감을 만든다.
- 부족한 점을 비난이 아니라 다음 훈련 힌트로 설명한다.
- Recovery와 연결해 “오늘 운동이 몸 상태에 어떤 영향을 줄 수 있는가”를 보여준다.
- 공유 가능한 운동 카드와 피드 경험으로 확장할 수 있는 기록 구조를 만든다.

좋은 운동 상세는 사용자가 “오늘 잘한 점 하나”와 “다음에 시도할 점 하나”를 가져가게 해야 한다.

## B. Workout Detail Core Sections

### 1. 운동 요약

운동 요약은 상세 화면의 첫 번째 기준점이다. 사용자가 3초 안에 운동의 규모와 성격을 이해해야 한다.

표시 후보:

- 거리
- 시간
- 평균 페이스 또는 평균 속도
- 칼로리
- 평균 심박
- 상승 고도
- 평균 파워, 사이클/러닝 파워가 있을 때
- 종목, 날짜, 위치

요약은 큰 수치만 나열하지 않고, 종목별로 가장 중요한 지표를 우선한다.

- 러닝: 거리, 시간, 평균 페이스, 평균 심박
- 사이클: 거리, 시간, 평균 속도, 평균 파워, 상승 고도
- 수영: 거리, 시간, 평균 페이스, 스트로크/랩
- 오픈워터: 거리, 시간, 경로, 페이스 편차

### 2. 성과

성과 섹션은 사용자가 성장을 느끼는 지점이다. PR이나 이전 기록 대비 개선이 있으면 명확하게 보여주되, 배지나 게임 요소가 운동 데이터보다 과하게 앞서지 않게 한다.

표시 후보:

- PR: 5K, 10K, 20분 파워, 최장 거리, 최장 시간
- 이전 같은 거리 대비 평균 페이스 개선
- 최근 4주 평균 대비 높은 훈련량
- 주간 누적 거리 증가
- 동일 코스 대비 속도/페이스 개선
- 꾸준함 성과: 이번 주 3회 운동, 4주 연속 기록

성과 문구는 “기록 경신”뿐 아니라 “꾸준함”도 성장으로 다룬다.

### 3. 부족한 점

부족한 점은 실패 평가가 아니라 다음 운동을 더 잘하기 위한 관찰이다. SOOM은 사용자를 혼내지 않고, 조용하고 구체적인 개선 힌트를 제공한다.

표시 후보:

- 페이스 흔들림: 후반 페이스 하락, 구간별 편차 증가
- 심박 과상승: 같은 페이스 대비 심박이 높음
- 후반 저하: 마지막 20~30% 구간에서 속도/파워 감소
- 고강도 과다: 목표 대비 높은 심박 존 또는 높은 RPE
- 회복 부족 신호: 최근 피로도 높은 상태에서 고강도 진행
- 파워/케이던스 불안정: 사이클 구간별 변동성 증가

부족한 점은 최대 1~2개만 보여준다. 너무 많은 지적은 사용자가 성장보다 실패를 먼저 느끼게 만든다.

### 4. 코칭 인사이트

코칭 인사이트는 운동 상세에서 가장 중요한 한 문장이다. 데이터 해석을 다음 운동 행동으로 연결한다.

원칙:

- 한 번의 상세 화면에서 개선 포인트는 1개가 가장 좋다.
- 문장은 짧고 행동 가능해야 한다.
- “다음 운동에서 무엇을 해볼지”가 드러나야 한다.
- 기록보다 몸 상태와 리듬을 함께 고려한다.

예:

- “다음 러닝에서는 첫 2 km를 조금 더 천천히 시작해 후반 리듬을 유지해보세요.”
- “오늘 파워는 안정적이었어요. 다음 사이클은 같은 강도로 10분만 더 이어가도 좋아요.”
- “심박이 빠르게 올라간 날이에요. 다음 운동은 워밍업을 조금 더 길게 가져가보세요.”

### 5. 회복 연결

Workout Detail은 Recovery와 경쟁하지 않는다. Recovery는 오늘의 몸 상태와 훈련 준비도를 설명하고, Workout Detail은 특정 운동이 성장과 회복에 남긴 영향을 설명한다.

회복 연결 표시 후보:

- 이 운동의 training load
- 최근 7일 부하에서 차지하는 비중
- 다음 24시간 회복 권장
- 고강도/저강도 분류
- Recovery 화면으로 이어지는 보조 링크

표현 원칙:

- “위험하다”보다 “회복을 섞으면 더 좋아요”처럼 부드럽게 말한다.
- 의료적 판단처럼 보이지 않게 한다.
- Recovery score를 재계산하거나 대체하지 않는다.

## C. Growth Metrics v1

Workout Growth v1은 복잡한 알고리즘보다 사용자가 이해하기 쉬운 성장 신호를 우선한다.

### 거리 증가

- 최근 4주 평균 대비 이번 운동 거리
- 같은 종목 최근 운동 대비 거리 증가
- 주간 누적 거리 증가

사용 예:

- “지난주보다 12% 더 오래 움직였어요.”
- “최근 러닝 평균보다 1.8 km 더 길게 달렸어요.”

### 평균 속도 / 페이스 변화

- 같은 거리 대비 평균 페이스 개선
- 같은 코스 대비 속도 변화
- 최근 4주 평균 페이스 대비 변화

주의:

- 페이스 개선만 성장을 의미하지 않는다.
- 저강도 운동에서는 “느린 페이스”도 좋은 훈련일 수 있다.

### 운동 시간 증가

- 운동 지속 시간 증가
- Z2 또는 저강도 지속 시간 증가
- 동일 강도에서 더 오래 유지한 시간

### 심박 안정성

- 같은 페이스 대비 평균 심박 변화
- 후반 심박 drift
- 심박 존 분포
- 고강도 구간 비율

초기 버전에서는 단순한 문구로 시작한다.

- “비슷한 페이스에서 심박이 더 안정적으로 유지됐어요.”
- “후반 심박이 조금 빨리 올라갔어요.”

### 운동 빈도

- 최근 7일 운동 횟수
- 최근 4주 주당 평균 운동 횟수
- 휴식일과 훈련일 균형

빈도는 습관 형성을 보여주는 핵심 지표다. 기록 경신이 없더라도 운동을 이어간 사실 자체를 성장으로 다룬다.

### 주간 누적 거리

- 종목별 주간 누적 거리
- 지난주 대비 증가율
- 급격한 증가 여부

주의:

- 급격한 증가를 무조건 긍정으로 표현하지 않는다.
- 부상 위험과 회복 필요성을 함께 설명한다.

### 최근 4주 변화

- 4주 거리 변화
- 4주 시간 변화
- 4주 평균 강도 변화
- 4주 운동 빈도 변화

Workout Detail에서는 이번 운동이 4주 흐름 안에서 어떤 의미인지 짧게 보여준다.

## D. Motivation Copy

SOOM의 성장 문구는 과장하지 않는다. 사용자가 자랑스럽게 느끼되, 다음 행동이 자연스럽게 떠오르게 한다.

좋은 문구:

- “지난주보다 12% 더 오래 움직였어요.”
- “후반 페이스가 조금 흔들렸지만, 전체 리듬은 좋아지고 있어요.”
- “오늘은 기록보다 꾸준함이 더 좋은 신호예요.”
- “비슷한 거리에서 심박이 더 안정적으로 유지됐어요.”
- “이번 주 세 번째 운동이에요. 루틴이 조금씩 자리 잡고 있어요.”
- “처음 10분을 차분하게 가져간 덕분에 후반 리듬이 안정적이었어요.”
- “오늘 부하는 높은 편이에요. 다음 운동은 회복 리듬을 섞으면 더 좋아요.”

피해야 할 문구:

- “실패했습니다.”
- “심박이 위험합니다.”
- “반드시 쉬어야 합니다.”
- “기록이 좋지 않습니다.”
- “노력이 부족합니다.”

톤 원칙:

- 사용자를 평가하지 않는다.
- 성장 신호와 개선 힌트를 같이 보여준다.
- 명령보다 제안을 사용한다.
- 성과가 없는 날에도 의미를 찾는다.

## E. Data Model Candidates

Workout Growth v1은 다음 모델 후보를 기준으로 설계한다. 아직 구현 모델이 아니라, 향후 SwiftUI 화면과 provider 계층을 만들 때의 계약 후보로 둔다.

### WorkoutGrowthSummary

운동 상세 상단 또는 요약 영역에서 이번 운동의 성장 의미를 압축한다.

후보 필드:

- `workoutId`
- `primaryMessage`
- `growthScoreLabel`
- `comparisonText`
- `highlightMetrics`
- `nextFocus`
- `dataQuality`

### WorkoutInsight

운동에서 발견한 성장 또는 개선 힌트를 표현한다.

후보 필드:

- `title`
- `message`
- `tone`: positive, neutral, caution
- `metricReference`
- `suggestedAction`

### WorkoutComparison

이전 운동, 최근 평균, 같은 코스와 비교한다.

후보 필드:

- `basis`: previousWorkout, fourWeekAverage, sameRoute, sameDistance
- `metric`
- `currentValue`
- `previousValue`
- `deltaText`
- `interpretation`

### PersonalRecord

PR 또는 의미 있는 기록을 표현한다.

후보 필드:

- `type`: distance, pace, speed, power, duration, segment
- `title`
- `value`
- `previousValue`
- `achievedAt`
- `badgeText`

### WeeklyProgressSummary

Workout Detail에서 이번 운동이 주간 흐름에 어떤 영향을 주는지 설명한다.

후보 필드:

- `weekStartDate`
- `sport`
- `totalDistance`
- `totalDuration`
- `workoutCount`
- `changeText`
- `loadWarningText`

### WorkoutGrowthInput

Workout Growth Experience는 장기적으로 기존 `Workout`에 직접 묶이지 않고, `UnifiedWorkout`에서 파생된 `WorkoutGrowthInput`을 기준으로 확장한다.

Growth 계산에 들어가는 `UnifiedWorkout` collection은 import pipeline 이후 정제된 primary workout 기준이어야 한다. Apple HealthKit, Garmin, Samsung Health, SOOM 수동 기록이 같은 운동을 중복으로 제공하면 주간 거리, 운동 시간, 운동 횟수가 과장될 수 있으므로, 중복 합산 방지는 Growth Experience의 기본 전제다. 표준 import 흐름은 [SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md](SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md)를 따르고, 상세 중복 정책은 [SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md](SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md)를 따른다.

Growth input 생성 전에는 `UnifiedWorkoutAnalysisInputSelector`를 적용해 사용자가 `분석 제외`로 표시한 workout을 제거한다. v1 selector는 `UnifiedWorkout -> WorkoutGrowthInput` 변환을 제공하지만, 현재 `WorkoutGrowthSummaryBuilder`와 `WorkoutWeaknessInsightBuilder`의 production 입력은 아직 교체하지 않는다. 이 정책은 주간 거리/시간/빈도 계산이 사용자가 제외한 중복 또는 불필요한 기록을 포함하지 않도록 하기 위한 준비 단계다.

구현된 역할:

- `WorkoutGrowthInput`: Growth 분석용 공통 입력 모델
- `UnifiedWorkoutToGrowthInputMapper`: HealthKit, Garmin, Samsung Health, SOOM 자체 기록을 같은 Growth 입력 형태로 정리하는 mapper
- `UnifiedWorkoutAnalysisInputSelector`: 분석 제외 workout을 제거한 뒤 Growth 입력 후보를 만든다.

보존하는 주요 정보:

- source
- workout type
- start date
- duration minutes
- distance km
- running/walking/hiking pace text
- cycling 중심 average speed
- average heart rate
- elevation gain
- active energy

현재 `WorkoutGrowthSummaryBuilder`와 `WorkoutWeaknessInsightBuilder`의 입력은 아직 교체하지 않는다. 이 mapper는 다음 단계에서 기존 `Workout` 기반 Growth 로직을 Unified source 기반으로 옮기기 위한 준비 레이어다.

## F. Future Feed / SNS Connection

Workout Growth Experience는 Feed/SNS 경험의 기반이 된다. 피드는 단순히 사진이나 응원만 보여주는 공간이 아니라, 사람들이 어떻게 운동하고 성장하는지 볼 수 있는 기록 네트워크가 되어야 한다.

확장 후보:

- 운동 기록을 카드로 공유
- 친구 피드에서 운동 요약, 지도, 성과 확인
- kudos/응원
- 댓글
- 클럽 내 주간 운동 흐름 공유
- 나와 비슷한 사람의 성장 흐름 참고
- 같은 코스 또는 같은 거리의 개선 흐름 비교

공유 카드 원칙:

- 개인의 건강 데이터가 과도하게 노출되지 않게 한다.
- 사용자가 공유할 항목을 선택할 수 있어야 한다.
- PR과 성과뿐 아니라 꾸준함, 회복성 운동, 루틴도 공유 가능한 가치로 다룬다.
- 다른 사람과 비교해 압박을 주기보다 참고와 응원을 중심으로 한다.

## Growth Summary MVP Status

Workout Growth Summary MVP는 운동 상세의 첫 성장 요약 레이어다. 현재 구현 범위는 “핵심 성장 신호 1개를 뽑아 카드로 보여주는 것”에 한정한다.

구현된 구성:

- `WorkoutGrowthSummary`: 운동 상세 성장 요약 도메인 모델
- `WorkoutGrowthSummaryBuilder`: 현재 운동과 최근 운동을 비교하는 규칙 기반 Builder
- `WorkoutGrowthCard`: 운동 상세에 표시되는 성장 요약 카드

MVP 규칙:

- 같은 종목의 이전 기록보다 거리가 의미 있게 늘면 `endurance`
- 비슷한 거리에서 평균 페이스가 개선되면 `pace`
- 같은 주 운동 빈도가 충분하면 `consistency`
- 후반 심박 흐름이 안정적이면 `recovery`
- 비교 데이터가 부족하면 `none`

Workout Detail 배치:

- 운동 요약 바로 아래에 `WorkoutGrowthCard`를 배치한다.
- 그래프, 스플릿, 심박 존보다 먼저 보여 사용자가 “오늘 좋아진 점”을 빠르게 이해하게 한다.
- Recovery 관련 점수나 추천은 변경하지 않는다.

## Weakness Insight MVP Status

Workout Weakness Insight MVP는 Growth Summary를 보완하는 “다음에 좋아질 수 있는 점” 레이어다. 목적은 사용자를 평가하는 것이 아니라, 다음 운동에서 하나만 의식하면 좋은 힌트를 부드럽게 제안하는 것이다.

구현된 구성:

- `WorkoutWeaknessInsight`: 운동 상세 개선 힌트 도메인 모델
- `WorkoutWeaknessInsightBuilder`: 현재 운동과 최근 운동 흐름에서 개선 포인트 1개를 선택하는 규칙 기반 Builder
- `WorkoutWeaknessCard`: 운동 상세에서 Growth 카드 아래에 표시되는 코칭 카드

MVP 규칙:

- 후반 페이스가 크게 느려지면 `pacing`
- 최근 강도 흐름 위에 오늘 운동 강도가 높으면 `recovery`
- 평균 심박이 최근 흐름보다 높으면 `heartRate`
- 최근 운동 간격이 불규칙하면 `consistency`
- 후반 페이스와 심박이 함께 흔들리면 `endurance`
- 비교 데이터가 충분하지 않으면 `none`

톤 원칙:

- “못했다”, “실패”, “나쁨”처럼 평가하는 표현을 쓰지 않는다.
- “조금 흔들렸어요”, “더 안정적일 수 있어요”, “다음에는…”처럼 행동 가능한 코칭 문장을 사용한다.
- warning card처럼 과하게 빨갛게 표현하지 않고, 부드러운 보조 톤을 사용한다.

Workout Detail 배치:

- `WorkoutGrowthCard` 바로 아래에 `WorkoutWeaknessCard`를 배치한다.
- 흐름은 “좋아진 점 → 다음에 좋아질 수 있는 점 → 그래프/스플릿 상세” 순서다.
- Recovery score/status/recommendation은 변경하지 않는다.

## Implementation Boundary v1

이 문서는 설계 기준과 MVP 연결 상태를 정의한다.

v1에서 아직 하지 않는다:

- 실제 Growth score 계산
- Feed/SNS 기능 구현
- Recovery score 변경
- HealthKit 데이터 직접 연결
- 서버/AI 분석 연결
- 복잡한 성장 차트 또는 ML 기반 예측

향후 구현 순서 후보:

1. PR / 비교 카드 분리
2. 최근 4주 변화 기반 WeeklyProgressSummary 연결

## Weekly Workout Progress MVP Status

Weekly Workout Progress MVP는 운동 상세의 개별 성장 신호를 넘어, 사용자가 이번 주 운동 흐름을 한눈에 이해하도록 돕는 성장 요약 레이어다. Recovery가 오늘의 회복 상태를 설명한다면, Weekly Workout Progress는 “이번 주 내가 얼마나 움직였고 어떤 리듬을 만들었는지”를 설명한다.

구현 범위:

- `WeeklyWorkoutProgress`: 최근 7일 운동 흐름 요약 도메인 모델
- `WeeklyWorkoutProgressBuilder`: 최근 운동 배열을 기준으로 현재 7일과 이전 7일을 비교하는 규칙 기반 Builder
- `WeeklyWorkoutProgressCard`: Analysis 화면에 표시되는 주간 성장 요약 카드

MVP 규칙:

- 운동 횟수가 늘면 꾸준함 흐름으로 해석한다.
- 총 거리가 늘면 지구력 기반 성장으로 해석한다.
- 총 운동 시간이 늘면 움직인 시간 증가로 해석한다.
- 기록이 없거나 너무 적으면 무리하게 판단하지 않고 기록 축적을 안내한다.
- Recovery score와 무관하게 Workout 데이터만 사용한다.

화면 배치:

- v1에서는 `AnalysisView` 상단에 “이번 주 운동 흐름” 카드로 배치한다.
- Home에는 추후 compact 카드 후보로 남긴다.
- Workout Detail에는 개별 운동 성장/개선 카드가 우선이며, Weekly Progress는 분석 탭의 주간 흐름 요약 역할을 맡는다.

톤 정책:

- “더 많이 해야 한다”보다 “리듬이 만들어지고 있다”에 집중한다.
- 가벼운 주간도 실패가 아니라 다음 리듬을 준비하는 흐름으로 표현한다.
- 복잡한 차트나 ML 예측 없이, 사용자가 바로 이해할 수 있는 한 줄 요약과 핵심 수치만 보여준다.

## UnifiedWorkout Weekly Progress 연결 v1

Weekly Workout Progress는 `UnifiedWorkoutStore`에 저장된 운동 기록을 `UnifiedWorkoutAnalysisInputSelector`로 필터링한 뒤 `WorkoutGrowthInput`으로 변환해 계산할 수 있다. 이 흐름을 통해 HealthKit import preview로 가져온 workout이 주간 성장 요약에 반영될 수 있다. `isExcludedFromAnalysis == true`인 운동은 Growth 입력에서 제외하며, Recovery score와는 분리한다.

## Analysis Architecture Cleanup v1

Analysis 화면은 Growth interpretation layer로 유지하며, SwiftData 조회와 `UnifiedWorkoutWeeklyProgressProvider` 호출 책임은 `AnalysisViewModel`과 `AnalysisViewContainer`로 분리한다. `AnalysisView`는 화면 구성과 기존 dashboard 표시만 담당하고, 가져온 `UnifiedWorkout` 기반 주간 성장 요약은 ViewModel을 통해 주입받는다.

## 4-Week Workout Growth Trend MVP

4주 운동 성장 추세 MVP는 주간 요약보다 긴 호흡으로 사용자의 운동 리듬이 커지고 있는지, 안정적인지, 또는 잠시 가벼워졌는지 보여주는 보조 성장 레이어다.

구현된 구성:

- `FourWeekWorkoutTrend`: 최근 4주 추세 도메인 모델
- `FourWeekWorkoutTrendBuilder`: `WorkoutGrowthInput`을 4개의 7일 구간으로 묶어 추세를 판단하는 규칙 기반 Builder
- `UnifiedWorkoutGrowthTrendProvider`: `UnifiedWorkoutStore`에서 가져온 workout을 selector와 mapper를 거쳐 4주 추세 입력으로 만든다
- `FourWeekWorkoutTrendCard`: Analysis 화면에서 주간 요약 아래에 표시되는 보조 동기부여 카드

MVP 규칙:

- 거리, 시간, 횟수가 점진적으로 증가하면 `improving`
- 큰 변화 없이 이어지면 `steady`
- 최근 주가 이전 흐름보다 낮으면 `lighter`
- 2주 미만의 기록만 있으면 `insufficientData`

경계:

- Recovery score/status/recommendation은 변경하지 않는다.
- DeduplicationEngine은 자동 적용하지 않는다. 사용자가 `분석 제외`로 표시한 workout만 `UnifiedWorkoutAnalysisInputSelector`가 제외한다.
- 복잡한 차트나 ML 예측 없이 미니 바와 짧은 코칭 문장으로 장기 흐름만 보여준다.

## Personal Record / Achievement MVP

Personal Record / Achievement MVP는 사용자가 자신의 최고 기록과 최근 성과를 확인하도록 돕는 성장 동기부여 레이어다. 목적은 경쟁이나 랭킹이 아니라 “내가 조금씩 좋아지고 있다”는 개인 성장 감각을 만드는 것이다.

구현된 구성:

- `PersonalRecord`: 개인 기록 도메인 모델
- `PersonalRecordBuilder`: `WorkoutGrowthInput` 배열에서 거리, 시간, 페이스, 평균 속도, 상승 고도, 주간 꾸준함 기록을 계산하는 규칙 기반 Builder
- `UnifiedWorkoutPersonalRecordProvider`: `UnifiedWorkoutStore`에서 workout을 가져와 selector와 mapper를 거쳐 개인 기록을 만든다
- `PersonalRecordCard`: Analysis 화면에서 PR/achievement를 차분하게 표시하는 카드

MVP 규칙:

- 최대 거리: 최근 입력 중 가장 긴 거리
- 최대 시간: 가장 오래 움직인 기록
- 최고 페이스: running/walking/hiking 기준 가장 낮은 분/km
- 최고 평균 속도: cycling 등 speed 중심 운동의 가장 높은 평균 속도
- 최고 상승 고도: 상승고도 50m 이상일 때 표시
- 주간 꾸준함: 최근 7일에 3회 이상 운동이 있으면 루틴 성과로 표시

경계:

- `isExcludedFromAnalysis == true`인 workout은 개인 기록 계산에서 제외한다.
- Recovery score/status/recommendation은 변경하지 않는다.
- 배지 시스템, 리더보드, Feed/SNS 공유는 아직 구현하지 않는다.
- 문구는 경쟁보다 개인 성장과 꾸준함을 중심으로 둔다.

## Workout Recovery Impact MVP

Workout Recovery Impact MVP는 개별 운동 상세에서 해당 운동이 회복 흐름에 어떤 영향을 줄 수 있는지 부드럽게 설명하는 interpretation layer다. 이 기능은 Recovery score를 다시 계산하지 않고, 운동 상세의 성장/개선 흐름과 Recovery 경험을 연결하는 첫 단계다.

구현된 구성:

- `WorkoutRecoveryImpact`: 회복 영향 도메인 모델
- `WorkoutRecoveryImpactBuilder`: `WorkoutGrowthInput`과 선택적 `RecoverySummary`를 읽어 회복 영향 문장을 만드는 규칙 기반 Builder
- `WorkoutRecoveryImpactCard`: Workout Detail에서 Growth/Weakness 아래에 표시되는 코칭 카드

MVP 규칙:

- 긴 운동 시간과 높은 평균 심박이 함께 있으면 회복 리듬을 조금 더 챙기는 흐름으로 해석한다.
- 회복 우선 상태에서 강도가 높은 운동이면 다음 운동 전 회복 확인을 제안한다.
- 짧고 낮은 심박의 운동은 recovery-friendly 활동으로 해석한다.
- 입력 데이터가 부족하면 판단하지 않고 기록 축적을 안내한다.

경계:

- `RecoveryCalculator`를 호출하거나 변경하지 않는다.
- Recovery score/status/recommendation은 변경하지 않는다.
- 이 카드는 진단이나 위험 경고가 아니라 다음 운동 전 확인하면 좋은 코칭 힌트다.
- Feed/SNS 공유, ML 예측, Garmin/Samsung 실제 연동은 포함하지 않는다.

## Workout Session Summary MVP

Workout Session Summary는 운동 상세에서 기본 수치 이후 가장 먼저 보이는 핵심 해석 레이어다. 기존 Growth Summary, Weakness Insight, Recovery Impact를 다시 계산하지 않고 조합해 사용자가 오늘 운동을 한 번에 이해하도록 돕는다.

- 흐름: 운동 기본 수치 → 오늘 운동 요약 → 좋아진 점 → 다음에 좋아질 점 → 회복 영향
- 역할: 성장, 개선 힌트, 회복 연결을 한 카드 안에서 짧게 요약한다.
- 정책: 새로운 점수 계산, Recovery score 변경, ML 예측은 하지 않는다.
- 톤: 부정적 평가보다 “다음 운동에서 더 좋아질 수 있는 힌트” 중심으로 표현한다.

## Shareable Workout Card Direction

Workout Session Summary, Personal Record, Weekly Progress는 장기적으로 공유 가능한 운동 카드의 기반이 된다. 공유 카드는 단순한 자랑이나 랭킹이 아니라 “성장, 리듬, 꾸준함”을 부드럽게 보여주는 동기부여 레이어다.

- Session Summary는 한 번의 운동을 공유하는 기본 카드 후보다.
- Weekly Progress는 이번 주 루틴과 누적 흐름을 공유하는 카드 후보다.
- Personal Record는 개인 성장 중심의 성과 카드 후보다.
- Recovery Impact는 회복 친화적 운동이나 다음 행동 힌트를 공유 가능한 문장으로 전환할 수 있다.

공유 카드 상세 기준은 [SOOM_SHAREABLE_WORKOUT_CARD.md](SOOM_SHAREABLE_WORKOUT_CARD.md)를 따른다.

## Workout Detail Growth Metrics v1

Workout Detail Growth Metrics v1은 운동 상세에서 `WorkoutGrowthInput` 기반의 세부 성장 지표를 보여주는 해석 레이어다. `WorkoutGrowthMetricsBuilder`는 현재 운동과 최근 운동 흐름을 비교해 거리, 운동 시간, 페이스 또는 평균 속도, 상승 고도, 심박 효율 후보를 3~5개 지표로 정리한다.

이 레이어는 “잘함/못함” 평가가 아니라 변화, 리듬, 흐름을 설명한다. 예를 들어 최근 평균보다 더 길게 움직였는지, 비슷한 심박에서 움직임 효율이 안정적인지, 오늘은 시간보다 리듬 유지에 가까운 운동인지처럼 행동 가능한 문장으로 표현한다.

배치 기준은 `WorkoutSessionSummaryCard` 아래, `WorkoutGrowthCard` 위다. 운동 기본 수치 이후 “오늘 운동 요약 -> 오늘 성장 데이터 -> 좋아진 점 -> 다음에 좋아질 점 -> 회복 영향” 흐름을 만든다.

### Type-aware Growth Baseline v1

Workout Detail Growth Metrics는 서로 다른 종목을 섞어 비교하지 않는다. 러닝은 러닝 기록과, 라이딩은 라이딩 기록과, 수영은 수영 기록과, 걷기/하이킹은 같은 걷기/하이킹 흐름과 비교한다. 같은 종목의 최근 기록이 부족하면 무리하게 다른 종목 평균을 끌어오지 않고 `insufficientData` 상태로 안내한다.

종목별 우선 지표는 `WorkoutTypeMetricProfile`로 정의한다.

- 러닝: 총거리, 총시간, 평균 페이스, 심박 효율 optional, 상승 고도 optional
- 라이딩: 총거리, 총시간, 평균 속도, 상승 고도, 심박 효율 optional
- 수영: 총거리, 총시간, 100m 페이스
- 걷기/하이킹: 총거리, 총시간, 평균 페이스, 상승 고도 optional

이 정책은 HealthKit/Garmin/Samsung/SOOM Local 데이터가 섞이더라도 Growth 비교의 기준을 “종목별 리듬”으로 유지하기 위한 v1 규칙이다.


## Route Comparison Insight v1

Route Comparison Insight adds a first “previous me” comparison layer to Workout Detail. It compares today’s workout with a previous similar route or similar-distance workout, then explains the difference with a few sport-specific metric rows.

Principles:

- Compare against the user’s own previous workouts, not a leaderboard.
- Keep route similarity simple in v1: distance tolerance, bounds overlap, and start/end proximity.
- Running emphasizes pace and distance, cycling emphasizes average speed/elevation, and swimming emphasizes 100m pace.
- If there is no useful baseline, show an insufficient-data state instead of forcing a judgement.
- RecoveryCalculator and existing Growth calculation policy remain unchanged.

## Workout Map Detail Expansion

Workout Detail은 장기적으로 Mapbox route map, sport-specific metrics, zone analysis를 결합한 상세 경험으로 확장한다. 요약 카드는 기록 리스트와 Feed에서 재사용하고, 상세 페이지는 interactive route map과 종목별 핵심 지표를 보여준다.

Route/Zone/Map/Zone Card 흐름은 `WorkoutRoute`, `WorkoutZone`, `WorkoutZoneSummary`, `WorkoutZoneBuilder`, HealthKit route/metric stream fetchers, Mapbox detail overlay, static route preview, and Zone Cards로 확장되었다. Route Comparison Insight v1은 이 route/growth 기반 위에서 같은 코스 또는 유사 운동 비교를 설명하는 첫 해석 레이어다.

자세한 설계는 [SOOM_WORKOUT_MAP_DETAIL_EXPERIENCE.md](SOOM_WORKOUT_MAP_DETAIL_EXPERIENCE.md)를 따른다. 이 확장은 Growth interpretation layer이며 RecoveryCalculator나 공식 Recovery score를 변경하지 않는다.

## Similar Workout Candidate Provider v1

Comparison Insight now has a store-backed candidate path for imported `UnifiedWorkout` detail. `SimilarWorkoutCandidateProvider` reads recent workouts from `UnifiedWorkoutStore`, excludes the current workout and any `isExcludedFromAnalysis` records, filters to the same workout type, and returns `WorkoutGrowthInput` candidates for comparison.

For v1, route ranking is optional. If current and candidate routes are available, `RouteSimilarityBuilder` can rank by route similarity. When route persistence is not available, the provider falls back to similar distance and recency. Mock/local workout detail continues to use the existing in-memory comparison flow. RecoveryCalculator and existing Growth calculation logic are unchanged.

## Split / Segment Insight v1

Workout Detail now includes a lightweight split interpretation layer focused on pacing rhythm rather than segment competition. `WorkoutSplitInsightBuilder` reads the current `WorkoutGrowthInput` and creates a simple “운동 흐름” insight from duration, distance, pace, or speed.

This is intentionally not GPS segment replay or Strava-style segment matching. v1 explains stable pace, stable speed, or a softer late-session rhythm check with coaching copy. RecoveryCalculator and existing Growth calculation logic remain unchanged.

## Workout Detail Growth Flow Grouping v1

Workout Detail now treats growth interpretation as a grouped reading flow rather than separate cards competing for attention. The `성장 흐름` group collects:

- `WorkoutGrowthMetricsCard`: concrete sport-specific metric changes.
- `WorkoutGrowthCard`: the single positive growth signal.
- `WorkoutComparisonInsightCard`: previous-me comparison.
- `WorkoutSplitInsightCard`: today’s internal pacing/rhythm cue.

This preserves the existing rule-based builders and keeps Growth interpretation separate from Recovery scoring. Zone data remains a supporting evidence layer after the growth group.
