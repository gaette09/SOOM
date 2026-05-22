# SOOM Unified Health Data Source v1

## A. Purpose

SOOM은 장기적으로 Apple HealthKit, Garmin, Samsung Health, SOOM 자체 기록처럼 서로 다른 건강/운동 데이터 소스를 함께 다뤄야 한다. 사용자는 한 플랫폼만 쓰지 않고, Apple Watch로 일상 데이터를 기록하면서 Garmin으로 라이딩을 기록하거나, 삼성 기기와 서드파티 운동 앱을 함께 사용할 수 있다.

Unified Health Data Source의 목적은 특정 플랫폼 API에 앱 경험을 직접 묶지 않고, SOOM이 이해할 수 있는 공통 도메인 모델로 먼저 정제하는 것이다. Recovery, Workout Growth, AI Coach, Feed/SNS 공유는 모두 원천 API가 아니라 SOOM 공통 모델을 읽도록 설계한다.

Workout import의 표준 흐름은 [SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md](SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md)를 따른다. 이 pipeline은 source fetch, source-specific mapping, `UnifiedWorkout` 생성, data quality evaluation, deduplication, derived input 생성을 분리해 Recovery/Growth/Feed가 정제된 workout만 사용하게 한다.

`UnifiedWorkoutRecord`와 `SwiftDataUnifiedWorkoutStore` v1이 구현되어 `UnifiedWorkout`의 로컬 source of truth 후보가 준비되었다. 다만 아직 HealthKit/Garmin/Samsung import pipeline과 자동 연결하지 않으며, Store는 fuzzy deduplication 없이 `externalId + source` 또는 `id` 기준 upsert만 담당한다.

원칙:

- 외부 source는 raw data provider이고, SOOM 경험은 unified domain model을 기준으로 동작한다.
- 플랫폼별 누락 필드와 추정 필드는 명시적으로 표시한다.
- RecoveryCalculator와 Workout Growth Builder는 source별 API를 직접 알지 않는다.
- HealthKit, Garmin, Samsung Health 연결은 모두 read-first 정책으로 시작한다.

## B. Supported Sources v1/v2

v1 준비 source:

- Apple HealthKit
- SOOM manual/internal workout records
- SOOM local workout snapshots

v2 이후 후보:

- Garmin Activity API
- Garmin Health API
- Samsung Health
- Android Health Connect
- 향후 서버 동기화 또는 코치 업로드 데이터

각 source의 역할:

- Apple HealthKit: iPhone/Apple Watch 기반 workout, heart rate, active energy, distance, sleep/HRV 후보
- Garmin Activity API: Garmin 기기에서 기록한 workout summary, route, power, cadence, lap/segment 데이터 후보
- Garmin Health API: sleep, stress, body battery, resting heart rate, HRV 후보
- Samsung Health / Health Connect: Android 기반 workout, sleep, heart rate, steps, energy 후보
- SOOM internal records: 앱 내 수동 기록, 더미/하네스 데이터, 향후 자체 기록 기능

## C. Unified Domain Models

### UnifiedDataSource

데이터가 어디서 왔는지 표현한다.

후보 필드:

- `sourceType`: healthKit, garminActivity, garminHealth, samsungHealth, healthConnect, soomManual, soomInternal
- `displayName`
- `externalSourceId`
- `permissionStatus`
- `lastSyncAt`

### UnifiedWorkout

운동 1개의 공통 summary 모델이다.

후보 필드:

- `id`
- `externalId`
- `source`
- `sportType`
- `startDate`
- `endDate`
- `duration`
- `distanceMeters`
- `activeCalories`
- `averageHeartRate`
- `maxHeartRate`
- `averagePower`
- `normalizedPower`
- `cadence`
- `elevationGain`
- `effort`
- `route`
- `streams`
- `laps`
- `dataQuality`

### UnifiedWorkoutStream

운동 중 시간 흐름 데이터를 표현한다.

후보 필드:

- `workoutId`
- `streamType`: heartRate, pace, speed, cadence, power, elevation, distance
- `samples`
- `samplingInterval`
- `source`
- `dataQuality`

### UnifiedHealthMetric

일상 건강 지표를 표현한다.

후보 필드:

- `metricType`: restingHeartRate, hrv, steps, stress, activeEnergy, sleepDuration, sleepQuality
- `value`
- `unit`
- `measuredAt`
- `source`
- `dataQuality`

### UnifiedSleepSummary

수면 요약을 표현한다.

후보 필드:

- `date`
- `startDate`
- `endDate`
- `durationMinutes`
- `sleepEfficiency`
- `deepSleepMinutes`
- `remSleepMinutes`
- `awakeMinutes`
- `source`
- `dataQuality`

### UnifiedRecoveryInput

RecoveryCalculator v2 이후로 전달될 통합 입력 후보이다.

후보 필드:

- `workouts`
- `healthMetrics`
- `sleepSummary`
- `checkIns`
- `sourceCoverage`
- `generatedAt`

## D. Source Mapping

Source별 mapping 방향:

- Apple HealthKit `HKWorkout` -> `HealthKitWorkout` -> `UnifiedWorkout`
- Garmin Activity -> `UnifiedWorkout`
- Samsung Health exercise -> `UnifiedWorkout`
- Health Connect exercise session -> `UnifiedWorkout`
- SOOM `LocalWorkoutSnapshot` -> `UnifiedWorkout`
- SOOM `Workout` -> `UnifiedWorkout`

현재 SOOM에는 이미 HealthKit 전용 `HealthKitWorkout`과 Recovery 전용 `RecoveryActivity`가 있다. Unified v1 설계는 이 구조를 바로 제거하지 않고, 다음 단계에서 `HealthKitWorkout -> UnifiedWorkout -> RecoveryActivity` 또는 `Workout -> UnifiedWorkout -> WorkoutGrowth input` 흐름으로 확장할 수 있게 한다.

Mapping 원칙:

- source별 원천 모델은 보존한다.
- 화면/계산 계층은 source별 원천 모델을 직접 읽지 않는다.
- 누락 필드는 nil 또는 estimated field로 명시한다.
- 단위는 Unified 모델에서 통일한다. 거리 meter, 시간 seconds 또는 minutes, energy kcal, heart rate bpm을 기준으로 한다.

## E. Data Categories

### Workout Summary

운동 카드, 운동 상세, Growth Summary, Weekly Workout Progress의 기본 입력이다.

포함 후보:

- sport type
- duration
- distance
- calories
- average/max heart rate
- average speed/pace
- power/cadence/elevation
- source
- achievements

### Workout Streams

운동 상세 그래프, 스플릿 분석, 후반 페이스 유지, 심박 안정성 판단에 사용한다.

포함 후보:

- heart rate stream
- pace/speed stream
- cadence stream
- power stream
- elevation stream
- distance/time stream

### Daily Health Metrics

Recovery v2 이후의 회복 계산 보조 입력이다.

포함 후보:

- resting heart rate
- HRV
- sleep duration / quality
- stress
- steps
- active energy
- resting calories

### Recovery Inputs

RecoveryCalculator 또는 향후 RecoveryInputBuilder가 사용할 입력이다.

포함 후보:

- 최근 workout load
- rest days
- subjective check-in
- sleep summary
- HRV/resting HR trend
- source confidence

### Growth Metrics

Workout/Growth 축에서 사용하는 입력이다.

포함 후보:

- weekly workout count
- total distance
- total duration
- pace/speed change
- heart rate stability
- streak/consistency
- recent 4-week trend

## F. Data Quality / Confidence

Unified 모델은 값 자체뿐 아니라 신뢰도도 함께 가져야 한다.

후보 필드:

- `source`: 데이터 출처
- `permissionStatus`: allowed, denied, partial, unknown
- `missingFields`: source에 없거나 권한이 없어 가져오지 못한 필드
- `estimatedFields`: SOOM이 추정한 값
- `duplicateCandidate`: 중복 가능성 여부
- `syncTimestamp`: 마지막 동기화 시점
- `confidence`: low, medium, high

예:

- Garmin workout에 power가 있으면 cycling load confidence를 높인다.
- HealthKit workout에 average heart rate가 없으면 trainingLoad는 estimated로 표시한다.
- 같은 운동이 HealthKit과 Garmin 양쪽에 있으면 duplicateCandidate로 표시한다.

## G. Deduplication Strategy

같은 운동이 Apple HealthKit과 Garmin 양쪽에서 들어올 수 있다. 예를 들어 Garmin으로 기록한 라이딩이 Apple 건강 앱에 동기화되면 SOOM은 같은 운동을 두 번 계산할 위험이 있다.

상세 정책은 [SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md](SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md)를 따른다. `UnifiedWorkoutDeduplicationEngine`은 import pipeline에 연결하기 전 단계로 준비되어 있으며, Recovery, Workout Growth, Feed/SNS에 데이터를 넘기기 전에 중복 후보를 감지하고 계산 계층에는 중복이 제거된 primary workout collection을 전달하는 방향으로 설계한다.

v1 문서화 기준:

- `externalId`가 같으면 같은 운동 후보로 본다.
- 시작 시간이 매우 가깝고 duration/distance가 유사하면 중복 후보로 본다.
- source priority를 둔다. 예: Garmin 원본 workout이 있고 HealthKit에 같은 workout이 있으면 Garmin을 primary로 선택할 수 있다.
- 중복 제거는 Recovery, Growth 계산 전에 수행한다.
- 삭제하지 않고 primary/duplicate 관계를 표시하는 방식도 후보로 둔다.

중복 판단 후보:

- startDate difference
- endDate difference
- duration similarity
- distance similarity
- sport type
- source bundle id 또는 device id
- external workout id

v1에서는 `UnifiedWorkoutDuplicateCandidate`와 `UnifiedWorkoutDeduplicationEngine` 순수 로직을 구현했지만, 아직 import pipeline에는 연결하지 않는다. 자동 삭제/자동 병합도 하지 않는다.

## H. Privacy / Consent

건강/운동 데이터는 민감 데이터로 취급한다.

정책:

- 사용자가 연결한 source만 읽는다.
- 기본은 read-only 권한이다.
- 앱 실행 또는 Recovery 화면 진입만으로 권한을 강제하지 않는다.
- 서버 동기화는 별도 동의가 필요하다.
- source별 연결/해제 상태를 사용자가 이해할 수 있어야 한다.
- 데이터가 부족한 경우 사용자를 탓하지 않고 부드럽게 안내한다.

문구 원칙:

- “진단”, “위험 판정”처럼 의료적으로 들리는 표현을 피한다.
- “추정”, “참고”, “추천”, “운동 컨디션” 중심으로 설명한다.
- 데이터 누락은 실패가 아니라 연결 상태/권한 상태로 안내한다.

## I. Future Implementation Plan

Phase 1: 문서/공통 모델 설계. 완료.

- Unified data source 방향 정리
- UnifiedWorkout, UnifiedHealthMetric, UnifiedRecoveryInput 후보 정의
- HealthKit/Garmin/Samsung/SOOM source mapping 정책 정리

Phase 2: UnifiedWorkout 모델 추가. 완료.

- Swift production 모델 추가
- `UnifiedDataSource`, `UnifiedWorkoutType`, `UnifiedDataQuality`, `UnifiedWorkout` 추가
- source, dataQuality, externalId, workout summary 필드 포함
- 아직 기존 RecoveryCalculator와 Growth Builder에는 연결하지 않음

Phase 3: HealthKitWorkout -> UnifiedWorkout mapper. 완료.

- 기존 `HealthKitWorkout`을 유지하면서 Unified mapping 계층 추가
- `HealthKitWorkoutToUnifiedWorkoutMapper` 추가
- HealthKit 전용 mapper test 추가

Phase 4: UnifiedWorkout -> RecoveryActivity / WorkoutGrowth input mapper. 완료.

- Recovery는 `UnifiedWorkoutToRecoveryActivityMapper`를 통해 `UnifiedWorkout`에서 `RecoveryActivity`를 파생한다.
- `RecoveryActivity`는 원본 workout이 아니라 RecoveryCalculator에 전달하기 위한 계산 입력 모델이다.
- Workout Growth는 `UnifiedWorkoutToGrowthInputMapper`를 통해 `WorkoutGrowthInput`을 파생한다.
- `WorkoutGrowthInput`은 Growth 분석용 공통 입력 모델이며 source, 종목, 거리, 시간, 페이스/속도, 심박, 고도, 칼로리 요약을 보존한다.
- 기존 RecoveryCalculator 공식과 Growth 규칙은 별도 단계에서만 변경한다.

Phase 5: Garmin connector 설계

- Garmin Activity API와 Garmin Health API 구분
- OAuth, sync window, duplicate handling 설계
- route/power/cadence/lap 데이터 mapping 검토

Phase 6: Samsung/Health Connect connector 설계

- Samsung Health와 Health Connect 지원 범위 조사
- Android-first source를 iOS 앱에서 어떻게 수용할지 서버/계정 동기화 후보 검토
- sleep/stress/steps mapping 기준 정리

Phase 7: UnifiedWorkout deduplication 설계/구현

- 기준 문서: [SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md](SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md)
- 중복 후보 모델과 confidence score 정의
- import pipeline에서 Recovery/Growth 계산 전 중복 제외
- 낮은 confidence 후보는 사용자 확인 UI로 보류

Phase 8: Unified Workout Import Pipeline 설계

- 기준 문서: [SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md](SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md)
- HealthKit/Garmin/Samsung/SOOM Local source를 `UnifiedWorkout`으로 정제하는 표준 흐름 정의
- data quality, deduplication, user/edit priority, derived input 생성 위치 정의
- 아직 Swift pipeline 구현은 하지 않음

Phase 9: UnifiedWorkoutStore SwiftData v1

- `UnifiedWorkoutRecord`, `UnifiedWorkoutPersistenceMapper`, `SwiftDataUnifiedWorkoutStore` 구현
- `UnifiedWorkout` 저장/조회/upsert/삭제와 분석 제외 flag 지원
- local source of truth 후보 준비
- 아직 import pipeline, DeduplicationEngine, Recovery/Growth derived input 흐름에는 연결하지 않음

Phase 10: HealthKit -> UnifiedWorkoutStore import pipeline v1

- `HealthKitWorkoutImportPipeline` 구현
- HealthKit workout fetch 결과를 `UnifiedWorkout`으로 변환한 뒤 `UnifiedWorkoutStore`에 저장
- HealthKit source가 SOOM의 공통 workout 저장소로 들어오는 첫 구현
- 아직 DeduplicationEngine, RecoveryActivity, WorkoutGrowthInput 생성 흐름에는 자동 연결하지 않음

Phase 11: Imported UnifiedWorkout Library MVP

- `UnifiedWorkoutLibraryView`, `UnifiedWorkoutLibraryViewModel`, `UnifiedWorkoutLibraryViewContainer` 구현
- `SwiftDataUnifiedWorkoutStore`에 저장된 최근 30일 운동 기록을 관리/검토 화면에서 확인
- 운동 타입, source, 날짜, 거리, duration, dataQuality, `isExcludedFromAnalysis` 상태 표시
- 아직 편집/삭제 UI, DeduplicationEngine 자동 적용, Recovery/Growth derived input 생성은 하지 않음

## Current Boundaries

이번 v1 문서 작업에서는 다음을 하지 않는다.

- Garmin/Samsung 실제 API 코드 추가
- HealthKit 기존 구현 변경
- RecoveryCalculator 변경
- Workout Growth Builder 변경
- Deduplication 구현
- 서버 동기화 구현

## Implementation Status

UnifiedWorkout Domain Model v1에서 추가된 Swift 모델:

- `UnifiedDataSource`: Apple HealthKit, Garmin, Samsung Health, Health Connect, SOOM local/manual, unknown source 표현
- `UnifiedWorkoutType`: running, cycling, walking, swimming, hiking, strength, yoga, other 표현
- `UnifiedDataQuality`: complete, partial, estimated, missing, unknown 표현
- `UnifiedWorkout`: source-independent workout summary 모델

현재 연결 상태:

- `HealthKitWorkout -> UnifiedWorkout` mapper 구현 완료
- `HealthKitWorkout -> UnifiedWorkoutStore` import pipeline 구현 완료
- `UnifiedWorkoutStore`에 저장된 workout을 확인하는 Library 화면 구현 완료
- `UnifiedWorkout -> RecoveryActivity` mapper 구현 완료
- `UnifiedWorkout -> WorkoutGrowthInput` mapper 구현 완료
- `UnifiedWorkout -> SwiftDataUnifiedWorkoutStore` 저장/조회 계층 구현 완료
- `RecoveryActivity`는 `UnifiedWorkout`에서 파생되는 계산 입력 모델로 취급
- `WorkoutGrowthInput`은 Growth 분석을 위한 source-independent 입력 모델로 취급
- 기존 `ActivityRecoveryDataProvider` 기본 source는 변경하지 않음
- `RecoveryCalculator`, Workout Growth Builder 입력 변경 없음
- Garmin/Samsung source는 문서와 모델 수용 범위만 준비됨

## UnifiedWorkout -> WorkoutGrowthInput -> WeeklyProgress

UnifiedWorkout 기반 Growth 흐름은 `UnifiedWorkoutStore` -> `UnifiedWorkoutAnalysisInputSelector` -> `UnifiedWorkoutToGrowthInputMapper` -> `WeeklyWorkoutProgressBuilder` 순서로 시작한다. 이 단계는 HealthKit import preview로 저장된 workout을 주간 성장 요약에 반영하기 위한 첫 연결이며, Recovery 계산과 DeduplicationEngine 자동 적용은 아직 분리되어 있다.


## UnifiedWorkout -> GrowthTrend Flow

UnifiedWorkout 기반 장기 성장 흐름은 `UnifiedWorkoutStore` -> `UnifiedWorkoutAnalysisInputSelector` -> `UnifiedWorkoutToGrowthInputMapper` -> `FourWeekWorkoutTrendBuilder` 순서로 계산한다. 이 연결은 HealthKit import preview로 저장된 workout이 Analysis 화면의 4주 성장 추세에 반영되는 첫 흐름이다.

현재 경계:

- `isExcludedFromAnalysis == true`인 workout은 4주 추세 입력에서 제외한다.
- DeduplicationEngine은 아직 자동 적용하지 않는다.
- RecoveryActivity 생성과 RecoveryCalculator 입력에는 연결하지 않는다.
- Garmin/Samsung 실제 import는 아직 구현하지 않는다.

## UnifiedWorkout -> RecoveryActivity -> Recovery Preview

UnifiedWorkout 기반 Recovery preview 흐름은 `UnifiedWorkoutStore` -> `UnifiedWorkoutAnalysisInputSelector` -> `UnifiedWorkoutToRecoveryActivityMapper` -> `RecoveryCalculator` 순서로 계산한다. 이 흐름은 HealthKit import preview로 저장된 workout을 Recovery 입력 후보로 검증하기 위한 preview layer이며, 기본 Recovery 화면의 provider를 교체하지 않는다.

현재 경계:

- `isExcludedFromAnalysis == true`인 workout은 Recovery preview 입력에서 제외한다.
- DeduplicationEngine은 아직 자동 적용하지 않는다.
- score/status/recommendation 공식은 기존 `RecoveryCalculator`를 그대로 사용한다.
- Garmin/Samsung 실제 import는 아직 구현하지 않는다.

## UnifiedWorkout / WorkoutGrowthInput Detail Metrics

`WorkoutGrowthInput`은 주간 성장 요약뿐 아니라 운동 상세 성장 지표의 공통 입력으로도 사용한다. HealthKit 또는 다른 source에서 들어온 `UnifiedWorkout`은 `UnifiedWorkoutToGrowthInputMapper`를 거쳐 거리, 시간, 페이스/속도, 심박, 상승 고도, 칼로리 요약을 보존하고, 이 값을 `WorkoutGrowthMetricsBuilder`가 상세 비교 지표로 해석할 수 있다.

이 흐름은 Growth interpretation layer이며 Recovery 공식 점수나 RecoveryCalculator를 변경하지 않는다. Garmin/Samsung source가 추가되더라도 동일한 `WorkoutGrowthInput` 계약을 통해 상세 성장 지표로 확장한다.
