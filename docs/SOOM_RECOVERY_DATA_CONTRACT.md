# SOOM Recovery Data Contract

SOOM Recovery는 HealthKit을 바로 연결하기 전에 화면이 필요로 하는 데이터 계약을 먼저 정의한다. 목표는 mock 데이터, 앱 자체 운동 기록, HealthKit, 서버/AI 분석 결과가 같은 `RecoverySummary` 형태로 화면에 전달되도록 만드는 것이다.

점수 계산식과 해석 기준은 [SOOM_RECOVERY_SCORE_FORMULA_V1.md](SOOM_RECOVERY_SCORE_FORMULA_V1.md)를 기준 문서로 둔다. 이 문서는 데이터 계약을 설명하고, Formula 문서는 `RecoveryCalculator`의 현재 MVP 점수 규칙과 향후 알고리즘 확장 방향을 설명한다.

일별 회복 기록 저장과 Timeline의 실제 데이터 전환 계획은 [SOOM_DAILY_RECOVERY_SNAPSHOT_PLAN.md](SOOM_DAILY_RECOVERY_SNAPSHOT_PLAN.md)를 따른다. Snapshot은 과거 `RecoverySummary` 결과 보관용이며 현재 score 계산 공식에 개입하지 않는다.

장기적으로 `RecoveryActivity`는 Apple HealthKit, Garmin, Samsung Health, SOOM 자체 기록을 정제한 `UnifiedWorkout`에서 파생된다. 통합 데이터 소스와 source mapping 기준은 [SOOM_UNIFIED_HEALTH_DATA_SOURCE.md](SOOM_UNIFIED_HEALTH_DATA_SOURCE.md)를 따른다. 여러 source에서 같은 운동이 들어올 수 있으므로, `RecoveryActivity` 생성 전에는 [SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md](SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md)를 통해 source fetch, unified mapping, data quality evaluation, deduplication을 거친 primary workout collection을 사용하는 것이 원칙이다. 세부 중복 판단 기준은 [SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md](SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md)를 따른다.

## 1. Screen Contract

`RecoveryView`는 `RecoveryViewModel`이 제공하는 `RecoverySummary`만 읽는다. 화면은 데이터 출처가 mock인지, HealthKit인지, 서버 계산값인지 알지 않는다.

현재 화면이 요구하는 데이터:

- `score`: 사용자에게는 0-100 감각의 회복 점수로 표시한다. 단, Formula v1의 내부 MVP 계산은 불필요하게 극단적인 메시지를 피하기 위해 45...95 범위로 clamp한다.
- `status`: 짧은 상태 라벨, 예: 좋음, 보통, 주의
- `description`: 점수의 이유를 설명하는 한두 문장
- `recommendation`: 오늘 권장 행동 요약
- `trendText`: 최근 변화 요약, 예: 지난 7일 대비 +6점
- `coachMessage`: AI 코치 이름, 부제, 메시지
- `recommendationCard`: 추천 행동 카드 제목, 설명, CTA 라벨, 아이콘
- `trends`: 휴식기 심박, 운동 부하, 피로도 등 변화 지표
- `insights`: 사용자가 이해해야 할 짧은 분석 문장
- `lastUpdated`: 데이터 기준 시각
- `dataQuality`: mock, estimated, high confidence 같은 신뢰도/완성도 상태

## 2. Possible HealthKit Inputs

HealthKit 연동 시 후보 데이터:

- Resting Heart Rate
- Heart Rate Variability
- Sleep Analysis
- Active Energy Burned
- Workout duration and workout type
- VO2 Max, 지원 기기/권한이 있는 경우
- Walking/Running distance
- Cycling distance, 지원 범위 확인 필요
- Mindful minutes 또는 회복 관련 생활 지표, v2 후보

HealthKit 권한 요청과 실제 API 호출은 이 문서 범위 밖이며, v1 mock 단계에서는 추가하지 않는다.

## 3. App-Owned Activity Inputs

SOOM 앱 자체 운동 기록에서 가져올 데이터:

- 최근 7일/30일 운동 횟수
- 종목별 거리, 시간, 빈도
- 고강도 세션 비율
- 스플릿, 심박 존, 파워 존
- 운동 부하 추정치
- 주관적 운동 강도, 피로도, 메모
- 휴식일 수와 연속 훈련일

운동 기록은 Recovery 계산 입력일 뿐 아니라 Workout Growth Experience의 핵심 데이터 원천이다. Recovery는 최근 운동 부하와 회복 상태를 해석하고, Workout Growth는 개별 운동 상세에서 성과, 이전 기록 대비 개선, 부족한 점, 다음 훈련 힌트를 설명한다. 현재 `WorkoutGrowthSummaryBuilder`는 `Workout`과 최근 운동 배열만 사용해 거리 증가, 페이스 개선, 운동 빈도, 후반 심박 안정성을 규칙 기반으로 해석한다. 이 흐름은 Recovery score/status/recommendation을 변경하지 않는다. 성장 경험 설계 기준은 [SOOM_WORKOUT_GROWTH_EXPERIENCE.md](SOOM_WORKOUT_GROWTH_EXPERIENCE.md)를 따른다.

현재 Activity 기반 MVP 입력 모델:

- `workoutType`: ride, run, swim, brick
- `durationMinutes`: 운동 시간
- `distanceKm`: 거리
- `averageHeartRate`: 평균 심박
- `relativeEffort`: 체감 강도 또는 세션 난이도 추정치
- `trainingLoad`: 세션 부하 추정치
- `completedAt`: 완료 시각

### Workout Mapping Strategy

SOOM 앱에는 현재 내부 운동 기록 모델인 `Workout`이 존재한다. Recovery 계층은 UI나 HealthKit에 직접 의존하지 않고, `RecoveryActivityMapper`를 통해 `Workout` 또는 임시 로컬 입력 모델을 `RecoveryActivity`로 변환한다.

매핑 기준:

- `Workout.sport` → `RecoveryWorkoutType`
- `Workout.duration` → `durationMinutes`
- `Workout.distanceMeters` → `distanceKm`
- `Workout.avgHeartRate` → `averageHeartRate`
- `Workout.effort` → `relativeEffort`
- `Workout.date` → `completedAt`
- `trainingLoad`는 아직 확정된 공식이 없으므로 duration, average heart rate, relative effort 기반의 단순 추정값을 사용한다.

`LocalWorkoutSnapshot`은 실제 로컬 DB/저장소가 붙기 전까지 `LocalActivityStore`가 사용할 임시 입력 모델이다. 이 모델은 HealthKit 전 단계에서 앱 내부 운동 기록 저장소와 Recovery 계산 계층 사이의 연결 지점을 검증하기 위해 유지한다.

Unified source 전환 이후에는 `Workout`, `LocalWorkoutSnapshot`, `HealthKitWorkout`, Garmin Activity, Samsung Health exercise를 먼저 import pipeline에서 `UnifiedWorkout`으로 정제하고, data quality와 deduplication 후보를 정리한 뒤, Recovery 계층은 deduped primary `UnifiedWorkout` collection에서 `UnifiedWorkoutToRecoveryActivityMapper`를 통해 `RecoveryActivity` 입력을 받는다. `RecoveryActivity`는 원본 운동 기록이 아니라 RecoveryCalculator에 전달하기 위한 파생 계산 모델이며, 원본 source와 상세 필드는 `UnifiedWorkout` 쪽에 보존한다.

RecoveryActivity 생성 전에는 `UnifiedWorkoutAnalysisInputSelector`를 적용해 `isExcludedFromAnalysis == true`인 workout을 제거하는 것이 원칙이다. v1 selector는 이미 포함/제외 필터와 `UnifiedWorkout -> RecoveryActivity` 변환을 제공하지만, production `RecoveryViewModel` 또는 `ActivityRecoveryDataProvider`에는 아직 자동 연결하지 않는다. 이 단계는 사용자 수동 제외 상태를 향후 Recovery 계산 입력에 반영하기 위한 준비 계층이다.

### Subjective Check-in Inputs

Subjective check-in은 사용자가 직접 입력하는 컨디션 기록이다. 이 데이터는 v2 Recovery 알고리즘 입력 후보이며, 현재 v1 `RecoveryCalculator`에는 연결하지 않는다. 입력 UX 원칙과 화면 설계 기준은 [SOOM_CHECKIN_UX_SPEC.md](SOOM_CHECKIN_UX_SPEC.md)를 따른다. 앱 재실행 후에도 check-in을 유지하기 위한 저장 전략은 [SOOM_CHECKIN_PERSISTENCE_PLAN.md](SOOM_CHECKIN_PERSISTENCE_PLAN.md)를 기준으로 검토하고, 실제 SwiftData 앱 연결은 [SOOM_SWIFTDATA_INTEGRATION_PLAN.md](SOOM_SWIFTDATA_INTEGRATION_PLAN.md)의 rollout 계획을 따른다.

Morning Check-in은 check-in의 v1 기본 사용 루프다. 앱 실행 후 Daily Readiness를 확인하고, 오늘 컨디션 기록이 없으면 10초 이내의 가벼운 기록을 제안한다. 전체 흐름과 상태 규칙은 [SOOM_MORNING_CHECKIN_FLOW.md](SOOM_MORNING_CHECKIN_FLOW.md)를 따른다.

현재 계약 모델:

- `RecoveryCheckIn`
  - `date`: 입력 기준 날짜
  - `fatigueLevel`: 피로도, 1...5
  - `sleepQuality`: 수면감, 1...5
  - `muscleSoreness`: 근육통, 1...5
  - `moodLevel`: 기분/컨디션, 1...5
  - `note`: 선택 메모
- `RecoveryCheckInSummary`
  - `latestCheckIn`: 가장 최근 입력
  - `weeklyAverageFatigue`: 최근 평균 피로도
  - `weeklyAverageSleepQuality`: 최근 평균 수면감
  - `weeklyAverageSoreness`: 최근 평균 근육통

현재 check-in 값은 모델 초기화 시 1...5 범위로 보정한다. 이는 UI, 저장소, 외부 데이터 입력이 생긴 뒤에도 계산 계층이 예상 가능한 스케일을 받도록 하기 위한 최소 안전장치다.

최신 check-in 표시 정책:

- `RecoveryViewModel`은 `RecoverySummary`와 별도로 최신 `RecoveryCheckIn`을 노출할 수 있다.
- check-in fetch 실패는 Recovery summary 로딩 실패로 처리하지 않는다.
- 최신 check-in은 Recovery 화면에서 부드러운 컨디션 요약 카드로만 표시한다.
- Morning loop에서는 오늘 또는 가장 최근 check-in을 우선 사용해 coach message와 insight를 개인화한다.
- 전체 History에는 모든 check-in 기록을 유지한다. 같은 날 여러 번 기록하더라도 Recovery 개인화에는 최신 기록만 사용한다.
- v1 score, status, recommendation은 check-in 유무와 관계없이 activity 기반 계산 결과를 유지한다.
- v1.5에서는 score formula를 변경하지 않고, 최신 check-in을 coachMessage와 insights 개인화에만 사용할 수 있다.

## 4. Computed Recovery Data

화면에 표시될 계산 데이터:

- Recovery score: 휴식기 심박, HRV, 수면, 최근 운동 부하, 주관 피로도를 조합한 대표 점수
- Fatigue score: 최근 운동 부하 증가, 고강도 비율, 휴식 부족을 반영한 피로 지표
- Training load: 최근 운동량과 강도 기반 부하
- Readiness status: 좋음, 보통, 주의 같은 사용자 친화 라벨
- Recommendation: 오늘 할 수 있는 운동 또는 휴식 행동
- Insight: 데이터 변화와 이유를 짧게 설명하는 문장
- Coach message: AI 분석 결과를 실행 가능한 코칭 문장으로 압축한 메시지

### Activity-Based MVP Calculation

`ActivityRecoveryDataProvider`는 `RecoveryActivityStore`에서 받은 SOOM 내부 운동 기록 형태의 `RecoveryActivity` 배열을 `RecoveryCalculator`로 전달한다. 현재는 실제 앱 DB가 아니라 `MockRecoveryActivityStore`가 제공하는 `RecoveryActivity.mockWeek`를 사용한다.

MVP 계산 흐름:

1. 최근 7일 운동 기록을 수집한다.
2. 최근 3일 `trainingLoad` 평균을 계산한다.
3. 최근 7일 `relativeEffort` 합계를 계산한다.
4. 최근 평균 심박과 7일 평균 심박 차이를 추세 문구로 만든다.
5. 활동이 없는 날짜를 휴식일로 추정한다.
6. 최근 부하와 체감 강도가 높으면 회복 점수를 낮추고, 휴식일이 있으면 점수를 올린다.
7. 점수와 부하에 따라 추천 행동, 인사이트, 코치 메시지를 생성한다.

현재 계산은 설명 가능한 규칙 기반 MVP이며, 의학적/생리학적 정확성을 목표로 하지 않는다.

## 5. Mock Data Status

현재 mock인 데이터:

- 회복 점수와 상태 라벨
- 평균 심박 추세
- 운동 부하 추세
- 피로도 추세
- AI 코치 메시지
- 인사이트와 추천 행동
- 데이터 품질 상태

Mock 데이터는 `RecoverySummary.mockToday`와 `RecoveryActivity.mockWeek`에서만 만든다. `RecoveryView`는 mock을 직접 참조하지 않고 `RecoveryViewModel`을 통해 표시한다. Activity 기반 화면 데이터는 `ActivityRecoveryDataProvider`가 `RecoveryActivityStore`를 통해 운동 기록을 요청한 뒤 `RecoveryCalculator`로 계산한다.

Recovery Timeline은 `DailyRecoverySnapshotStore`에서 저장된 일별 snapshot을 읽어 표시한다. 이 전환은 `RecoveryCalculator` 로직을 변경하지 않고, 계산된 일별 `RecoverySummary` 결과를 보관하고 읽는 방식으로 진행한다. 저장된 snapshot이 없으면 fake history를 만들지 않고 empty state를 표시한다.

Recovery 화면 진입 시 `RecoveryViewModel`은 오늘의 `RecoverySummary`를 성공적으로 로드한 뒤 `DailyRecoverySnapshotWriter`를 통해 오늘 snapshot 저장을 시도한다. 이 저장은 Timeline을 채우기 위한 historical layer이며, 저장 실패가 Recovery 요약 표시를 막지 않는다.

### Daily Recovery Snapshot Candidate

`DailyRecoverySnapshot`은 특정 날짜에 계산된 Recovery 결과를 저장하기 위한 후보 계약이다.

후보 필드:

- `id`
- `date`
- `score`
- `status`
- `recommendation`
- `coachMessage`
- `explanation`
- `dataQuality`
- `activityCount`
- `checkInId`
- `createdAt`
- `updatedAt`

역할:

- `RecoveryCalculator`는 현재 상태 계산을 담당한다.
- `DailyRecoverySnapshot`은 특정 날짜의 결과 저장을 담당한다.
- `DailyRecoverySnapshotWriter`는 `RecoverySummary`를 오늘 날짜의 snapshot으로 변환하고 저장한다.
- `RecoveryTimelineBuilder`는 snapshot을 `RecoveryTimelineEntry`로 변환한다.
- `RecoveryTimelineCard`는 snapshot 기반 entry를 읽어 최근 흐름을 보여준다.
- check-in 삭제/수정 또는 운동 기록 변경 시 과거 snapshot 재생성 정책은 v2에서 결정한다.

현재 구현 상태:

- `DailyRecoverySnapshot` 도메인 모델이 있다.
- `DailyRecoverySnapshotRecord` SwiftData record가 있다.
- `SwiftDataDailyRecoverySnapshotStore`는 저장, 최근 조회, 날짜 조회, 삭제를 지원한다.
- 같은 calendar day에 snapshot이 이미 있으면 새 record를 만들지 않고 기존 record를 update/upsert한다.
- 앱 전역 SwiftData `ModelContainer`에는 `CheckInRecord`와 `DailyRecoverySnapshotRecord`가 함께 등록되어 있다.
- Production `RecoveryViewContainer`는 `SwiftDataDailyRecoverySnapshotStore`를 `RecoveryTimelineBuilder`에 주입한다.
- Production `RecoveryViewContainer`는 같은 snapshot store를 `DailyRecoverySnapshotWriter`에도 주입한다.
- `RecoveryViewModel`은 summary와 latest check-in 개인화를 적용한 뒤 오늘 snapshot을 저장하고 Timeline을 다시 읽는다.
- Timeline은 snapshot store 기반이며, `RecoveryViewModel.reload()` 시 최신 snapshot을 다시 읽는다.
- snapshot 저장 실패는 `errorMessage`로 올리지 않고 조용히 무시한다. Recovery score/status/recommendation 화면 표시가 snapshot 저장 성공 여부에 의존하지 않게 하기 위함이다.

## 6. Provider Layer

Recovery 화면 데이터 공급은 `RecoveryDataProvider` 프로토콜을 통해 추상화한다.

```swift
protocol RecoveryDataProvider {
    func fetchRecoverySummary() async throws -> RecoverySummary
}
```

현재 provider:

- `MockRecoveryDataProvider`: `RecoverySummary.mockToday`를 반환한다. HealthKit, 네트워크, 서버 호출은 하지 않는다.
- `ActivityRecoveryDataProvider`: `RecoveryActivityStore`에서 최근 운동 기록을 받아 `RecoveryCalculator`에 전달한다. 현재 기본 provider다.
- `CombinedRecoveryDataProvider`: `RecoveryActivityStore`와 `RecoveryCheckInStore`를 함께 호출한다. v1 점수는 여전히 activity 기반 `RecoveryCalculator` 결과만 사용하고, check-in은 v2 확장을 위한 입력으로만 가져온다.

향후 provider:

- `HealthKitRecoveryDataProvider`: HealthKit 수면, HRV, 휴식기 심박, 활동 에너지 같은 원천 데이터를 읽어 `RecoverySummary` 계산 입력으로 제공한다.
- `ActivityRecoveryDataProvider`: SOOM 앱 내부 운동 기록, 심박 존, 파워 존, 최근 훈련량, 휴식일 데이터를 사용한다.
- `CombinedRecoveryDataProvider`: HealthKit 데이터와 앱 내부 운동 기록을 합쳐 회복 점수, 피로도, 추천 행동을 계산한다.

`RecoveryViewModel`은 provider만 알고, mock/HealthKit/Activity 중 어떤 구현인지 알지 않는다. `RecoveryView`는 ViewModel의 `summary`, `isLoading`, `errorMessage` 상태만 읽는다.

### Combined Provider Preparation

`CombinedRecoveryDataProvider`는 v2 통합 계산을 위한 준비 계층이다. 현재 `RecoveryViewModel`의 기본 provider는 `ActivityRecoveryDataProvider`로 유지하며, Combined provider는 아직 화면 기본 흐름에 연결하지 않는다.

현재 흐름:

1. 최근 7일 `RecoveryActivity`를 가져온다.
2. 최근 7일 `RecoveryCheckIn`을 가져온다.
3. `RecoveryInputContext`를 만든다.
4. v1 점수 계산은 `context.activities`만 `RecoveryCalculator`에 전달한다.
5. `context.checkIns`는 fetch와 summary 생성 가능 여부만 확인하며, v1 score/status/recommendation에는 반영하지 않는다.

`RecoveryInputContext` 필드:

- `activities`: 운동 기록 기반 회복 입력
- `checkIns`: 사용자가 직접 입력한 컨디션 기록
- `generatedAt`: 통합 입력 생성 시각

## 7. Activity Store Layer

Activity 기반 Recovery 입력은 `RecoveryActivityStore` 프로토콜로 한 번 더 분리한다. 이 계층은 provider가 mock 배열, 로컬 DB, HealthKit, 서버 중 어떤 원천에서 운동 기록이 오는지 알지 않게 만든다.

```swift
protocol RecoveryActivityStore {
    func fetchRecentActivities(days: Int) async throws -> [RecoveryActivity]
}
```

현재 store:

- `MockRecoveryActivityStore`: `RecoveryActivity.mockWeek`를 반환하고 `days` 기준으로 간단히 필터링한다. 실제 저장소, DB, HealthKit, 서버 호출은 하지 않는다.
- `LocalActivityStore`: 현재는 `LocalWorkoutSnapshot.mockRecent`를 읽고 `RecoveryActivityMapper`를 통해 `[RecoveryActivity]`로 변환한다. 실제 DB/서버 연결은 하지 않으며, 향후 앱 내부 운동 기록 저장소를 붙이기 위한 구조 초안이다.
- `HealthKitActivityStore`: `HealthKitWorkoutFetcher`가 읽은 `HealthKitWorkout`을 `HealthKitRecoveryActivityMapper`로 변환해 `[RecoveryActivity]`를 반환할 수 있는 future store다. 현재 production 기본 store로 연결하지 않으며, HealthKit fetch 실패 시 빈 배열로 안전하게 fallback한다.
- `MockRecoveryCheckInStore`: `RecoveryCheckIn.mockRecent`를 반환하고 `days` 기준으로 필터링한다. 실제 입력 UI, DB, 서버 호출은 하지 않는다.

향후 store:

- `LocalActivityStore`: SOOM 앱 내부 운동 기록 저장소에서 최근 운동을 읽고 `RecoveryActivityMapper`를 통해 계산 입력으로 변환한다.
- `LocalCheckInStore`: 사용자가 앱에서 입력한 check-in 기록을 로컬 저장소에서 읽는다.
- `HealthKitActivityStore`: 권한 UX와 feature flag가 준비된 뒤 `ActivityRecoveryDataProvider`에 주입 가능한 store 후보로 승격한다.
- `ServerActivityStore`: 서버에 저장된 운동 기록 또는 서버 계산 값을 받아온다.

`ActivityRecoveryDataProvider`는 store와 calculator만 알고, store 구현체가 어디서 데이터를 가져오는지는 알지 않는다. 기록이 비어 있을 때의 중립 회복 점수와 “데이터 부족” 상태도 calculator에서 생성한다.

### Mapper Layer

`RecoveryActivityMapper`는 앱 내부 운동 모델과 Recovery 계산 모델 사이의 변환 책임만 가진다. 이 계층을 분리하는 이유는 다음과 같다.

- `Workout` 모델이 화면 상세 표시를 위해 커져도 Recovery 계산 모델을 작고 안정적으로 유지한다.
- HealthKit, 로컬 DB, 서버 등 입력 출처가 늘어나도 `RecoveryCalculator`는 계속 `[RecoveryActivity]`만 받는다.
- `trainingLoad` 공식이 바뀌어도 변환/추정 로직을 mapper 또는 향후 calculator 입력 생성 단계에서 좁게 교체할 수 있다.

현재 `LocalActivityStore`는 실제 저장소 대신 `LocalWorkoutSnapshot.mockRecent`를 사용한다. 이 mock은 앱 내부 Workout 저장소가 준비되기 전까지 Local store 흐름을 빌드와 테스트에서 검증하기 위한 임시 장치다.

`HealthKitRecoveryActivityMapper`는 HealthKit 전용 workout snapshot을 Recovery 계산 입력으로 변환한다. 이 mapper의 `relativeEffort`와 `trainingLoad`는 아직 단순 추정값이며, v2에서 TRIMP, HR zone, power, sport-specific load를 반영할 때 교체한다. 이 계층은 `RecoveryCalculator` 공식을 바꾸지 않고 입력 변환 정책만 좁게 다루기 위해 유지한다.

`UnifiedWorkoutToRecoveryActivityMapper`는 source-independent `UnifiedWorkout`을 `RecoveryActivity`로 변환한다. 이 mapper는 Apple HealthKit, Garmin, Samsung Health, SOOM local/manual source가 같은 Recovery 계산 입력 구조로 들어올 수 있게 하는 공통 변환 계층이다. 현재는 `ActivityRecoveryDataProvider` 기본 source를 바꾸지 않으며, `trainingLoad`와 `relativeEffort`는 duration, heart rate, active energy 기반 MVP 추정값으로만 계산한다.

### Check-in Store Layer

`RecoveryCheckInStore`는 subjective check-in 입력을 추상화한다.

```swift
protocol RecoveryCheckInStore {
    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn]
}
```

수정/삭제 기능은 별도 계약으로 분리한다.

```swift
protocol RecoveryCheckInEditableStore: RecoveryCheckInWritableStore {
    func updateCheckIn(_ checkIn: RecoveryCheckIn) async throws
    func deleteCheckIn(id: UUID) async throws
    func deleteAllCheckIns() async throws
}
```

이 계약은 향후 Check-in 수정/삭제 UI, 설정의 전체 삭제, 개인정보 메뉴에서 사용한다. `RecoveryViewModel`과 `CheckInViewModel`은 현재 저장/읽기 흐름에 필요한 최소 프로토콜에만 의존하며, 수정/삭제 UI가 생기기 전까지 editable store에 직접 의존하지 않는다.

현재 구현체:

- `MockRecoveryCheckInStore`: 최근 check-in mock 데이터를 반환한다.
- `SwiftDataCheckInStore`: SwiftData 기반 check-in 저장소다. `RecoveryCheckInStore`, `RecoveryCheckInWritableStore`, `RecoveryCheckInEditableStore`를 채택하며, in-memory SwiftData 테스트를 통과했다. Production `CheckInViewContainer`는 저장에, `RecoveryViewContainer`는 latest check-in 읽기에 같은 앱 전역 SwiftData `ModelContainer`를 사용한다. `CheckInViewModel`과 `RecoveryViewModel`의 기본 init은 Preview/Test/rollback을 위해 mock store를 유지한다.

향후 구현체:

- `LocalCheckInStore`: 앱 내부 저장소에서 사용자가 직접 입력한 check-in 기록을 읽는다.
- `LocalPersistentCheckInStore`: JSON file storage 기반 임시 local persistence 후보로, SwiftData 도입 전 빠른 검증에 사용할 수 있다.
- `ServerCheckInStore`: 계정 기반 동기화가 필요할 때 서버의 check-in 기록을 읽는다.

이 계층은 latest check-in 표시와 v1.5 coach message/insight 개인화에 사용한다. `RecoveryView`가 다시 나타나거나 `RecoveryViewModel.reload()`가 호출되면 `RecoveryViewModel`은 SwiftData source of truth에서 latest check-in을 다시 읽고 `RecoverySummaryComposer`를 재적용한다. `ActivityRecoveryDataProvider`와 `RecoveryCalculator`의 score/status/recommendation 계산 입력에는 연결하지 않는다. v2에서 `CombinedRecoveryDataProvider` 또는 별도 score input builder가 activity, HealthKit, check-in 데이터를 병합할 때 사용한다.

삭제 정책:

- 단일 check-in 삭제는 latest summary 표시와 개인화 입력에서 해당 기록을 제거한다.
- 수정/삭제 후 Recovery 화면은 latest check-in을 다시 읽어 coach message와 insight 개인화만 갱신한다.
- 전체 삭제는 설정/개인정보 메뉴 후보이며, 서버 동기화 전에는 로컬 SwiftData 삭제가 source of truth다.
- check-in 수정/삭제는 Recovery score/status/recommendation을 변경하지 않는다.

## 8. Calculator Layer

`RecoveryCalculator`는 `[RecoveryActivity]`를 받아 `RecoverySummary`를 만드는 순수 계산 계층이다. provider는 fetch와 흐름 조합만 담당하고, 점수, 트렌드, 인사이트, 추천 행동, 코치 메시지 계산은 calculator가 담당한다.

```swift
struct RecoveryCalculator {
    func calculateSummary(from activities: [RecoveryActivity]) -> RecoverySummary
}
```

현재 MVP 계산 방식:

- 최근 3일 `trainingLoad` 평균으로 단기 부하를 추정한다.
- 최근 7일 `relativeEffort` 합계로 체감 강도 누적을 추정한다.
- 최근 7일 활동일을 기준으로 휴식일을 추정한다.
- 단기 부하와 체감 강도가 높으면 회복 점수를 낮추고, 휴식일이 있으면 회복 점수를 올린다.
- 운동 부하, 피로도, 평균 심박 트렌드를 `RecoveryTrend`로 만든다.
- 점수와 부하 상태를 바탕으로 추천 행동, 코치 메시지, 인사이트를 만든다.
- 입력 활동이 비어 있으면 중립 점수와 데이터 부족 상태를 반환한다.

향후 알고리즘 확장:

- TRIMP 기반 부하 계산
- HRV, 수면, 휴식기 심박 반영
- 사용자별 장기 기준선 반영
- 서버/AI 기반 코칭 메시지 병합
- ML 점수 또는 부상 위험 추정 모델 연결

`RecoveryCalculator`는 HealthKit, DB, 서버에 직접 접근하지 않는다. 이 구조를 유지하면 Unit Test에서 mock activity 배열만 넣어 점수와 메시지 결과를 검증할 수 있다.

알고리즘 변경 원칙:

- `RecoveryCalculator`는 순수 계산 계층이므로 알고리즘 변경 시 Unit Test를 먼저 갱신하거나 추가한다.
- 점수 범위, 빈 데이터 처리, 높은 부하 경고, 휴식 반영, trends/insights 생성은 회귀 테스트 대상으로 유지한다.

## 9. Coach Message Personalization Layer

`RecoveryCoachMessagePersonalizer`는 `RecoverySummary`와 최신 `RecoveryCheckIn`을 받아 coach message 문장만 개인화한다.

책임:

- score, status, description, recommendation, trends, insights는 변경하지 않는다.
- check-in이 없으면 기존 coach message를 그대로 유지한다.
- 피로감, 수면감, 근육통, 기분 값이 뚜렷할 때만 부드러운 코칭 문장으로 교체한다.
- 의료/진단 표현 대신 회복, 강도 조절, 가벼운 움직임 같은 행동 가능한 표현을 사용한다.

이 계층은 v1.5 준비 구조이며, check-in을 score formula에 반영하는 v2 알고리즘과 분리한다.

## 10. Check-in Signal Layer

`RecoveryCheckInSignalClassifier`는 최신 `RecoveryCheckIn`을 `RecoveryCheckInSignal`로 분류한다. Coach message와 insight 개인화가 같은 조건을 각자 판단하지 않도록 피로감, 수면감, 근육통, 기분 우선순위를 중앙화한다.

우선순위:

1. `highFatigue`
2. `lowSleep`
3. `highSoreness`
4. `lowMood`
5. `stable`

이 계층은 score, status, recommendation을 직접 변경하지 않는다.

## 11. Insight Personalization Layer

`RecoveryInsightPersonalizer`는 `RecoverySummary`와 최신 `RecoveryCheckIn`을 받아 insights 배열 앞에 개인화 insight 1개를 추가한다.

책임:

- score, status, description, recommendation, coach message, trends는 변경하지 않는다.
- check-in이 없거나 뚜렷한 신호가 없으면 기존 insights를 그대로 유지한다.
- 우선순위는 피로감, 수면감, 근육통, 기분 순서로 판단한다.
- 한 번에 여러 warning을 쌓지 않고, 사용자에게 가장 중요한 컨디션 맥락 1개만 보여준다.
- 의료/진단 표현 대신 회복 리듬, 가벼운 움직임, 목표 조절 같은 행동 가능한 표현을 사용한다.

이 계층도 v1.5 준비 구조이며, check-in 기반 score 보정과는 분리한다.

## 12. Summary Composition Layer

`RecoverySummaryComposer`는 activity 기반 `RecoverySummary`와 최신 `RecoveryCheckIn`을 받아 화면에 표시할 최종 `RecoverySummary`를 만든다.

적용 순서:

1. base activity summary
2. `RecoveryCoachMessagePersonalizer`
3. `RecoveryInsightPersonalizer`
4. final summary

책임:

- score, status, recommendation, trends는 변경하지 않는다.
- check-in이 없으면 base summary를 유지한다.
- check-in fetch 실패 시에도 activity 기반 Recovery 화면은 유지한다.

## 13. Recovery Activity Source / Provider Factory

`RecoveryActivitySource`는 Recovery 계산에 사용할 activity 입력 후보를 내부적으로 표현한다.

- `mock`: `MockRecoveryActivityStore` 기반. 현재 기본 Recovery 흐름이다.
- `local`: `LocalActivityStore` 기반. 앱 내부 workout snapshot을 RecoveryActivity로 변환하는 후보이다.
- `healthKit`: `HealthKitActivityStore` 기반. HealthKit workout을 RecoveryActivity로 변환하는 개발용 검증 후보이다.

`RecoveryDataProviderFactory`는 source에 따라 `ActivityRecoveryDataProvider`와 적절한 `RecoveryActivityStore`를 조합한다. 이 factory는 source 선택을 한 곳에 모아 두기 위한 구조이며, HealthKit을 production 기본값으로 바꾸는 기능이 아니다.

정책:

- 기본 source는 기존 mock-backed 흐름을 유지한다.
- HealthKit source는 내부 개발용 feature flag처럼만 사용한다.
- 사용자용 source 선택 UI는 제공하지 않는다.
- source를 바꿔도 `RecoveryCalculator` 공식, score/status/recommendation 정책은 변경하지 않는다.
- HealthKit 권한 요청은 provider 생성 시점에 발생하지 않는다.

## 14. v1 / v2 Expansion Plan

### v1

- Recovery 화면은 `RecoverySummary` 계약을 기준으로 유지한다.
- 데이터 공급자는 `ActivityRecoveryDataProvider`에서 시작하고, 실제 앱 운동 기록 저장소가 준비되면 `MockRecoveryActivityStore`를 `LocalActivityStore`로 교체한다.
- HealthKit 연결 전 권한, 데이터 누락, 신뢰도 상태를 설계한다.
- TRIMP, HRV, 수면 데이터는 아직 사용하지 않는다.

### v2

- HealthKit 수면, HRV, 휴식기 심박을 연결한다.
- TRIMP, HRV, 수면, 장기 개인 기준선을 합쳐 회복 점수 알고리즘을 개선한다.
- 사용자별 기준선을 계산해 개인화된 회복 점수를 만든다.
- 운동 계획, AI 코칭, 부상 위험 예측과 연결한다.
- `dataQuality`를 UI에 표시해 데이터가 부족한 상황을 투명하게 안내한다.

## 15. Workout Recovery Impact Interpretation Layer

`WorkoutRecoveryImpact`는 운동 상세 화면에서 `WorkoutGrowthInput`과 선택적 `RecoverySummary`를 읽어 “이 운동이 회복 흐름에 어떤 영향을 줄 수 있는지” 설명하는 해석 계층이다. 이 계층은 Recovery score/status/recommendation을 계산하거나 수정하지 않는다.

정책:

- `RecoveryCalculator` 공식은 변경하지 않는다.
- `RecoverySummary`가 전달되더라도 읽기 전용 맥락으로만 사용한다.
- 운동 상세에서는 Growth Summary, Weakness Insight와 함께 사용자의 다음 운동 판단을 돕는 코칭 문장으로만 표시한다.
- 문구는 의료/진단 표현이 아니라 “회복 리듬”, “다음 운동 전 확인”, “가벼운 마무리”처럼 행동 가능한 표현을 사용한다.

## 16. UnifiedWorkout Recovery Real Data Preview

Recovery Real Data Preview는 `UnifiedWorkoutStore`에 저장된 실제 운동 기록을 기반으로 RecoverySummary를 미리 계산해 보는 검증/관리 흐름이다. 기본 Recovery 화면의 provider를 교체하지 않고, 가져온 운동 기록이 향후 Recovery 입력으로 사용할 수 있는지 확인하는 preview layer로 둔다.

데이터 흐름:

1. `UnifiedWorkoutStore`에서 최근 workout 조회
2. `UnifiedWorkoutAnalysisInputSelector`로 `isExcludedFromAnalysis == true` workout 제외
3. `UnifiedWorkoutToRecoveryActivityMapper`로 `RecoveryActivity` 파생
4. 기존 `RecoveryCalculator.calculateSummary(from:)` 호출
5. `RecoveryRealDataPreviewView`에서 score/status/recommendation/dataQuality/사용 workout 수 표시

정책:

- `RecoveryCalculator` 공식과 score/status/recommendation 계산식은 변경하지 않는다.
- 기본 `RecoveryViewModel` provider에는 연결하지 않는다.
- DeduplicationEngine은 자동 적용하지 않는다.
- HealthKit source를 기본 Recovery source로 바꾸지 않는다.
- excluded workout은 preview 계산 입력에서 반드시 제외한다.

