# SOOM Unified Health Data Source v1

## A. Purpose

SOOM은 장기적으로 Apple HealthKit, Garmin, Samsung Health, SOOM 자체 기록처럼 서로 다른 건강/운동 데이터 소스를 함께 다뤄야 한다. 사용자는 한 플랫폼만 쓰지 않고, Apple Watch로 일상 데이터를 기록하면서 Garmin으로 라이딩을 기록하거나, 삼성 기기와 서드파티 운동 앱을 함께 사용할 수 있다.

Unified Health Data Source의 목적은 특정 플랫폼 API에 앱 경험을 직접 묶지 않고, SOOM이 이해할 수 있는 공통 도메인 모델로 먼저 정제하는 것이다. Recovery, Workout Growth, AI Coach, Feed/SNS 공유는 모두 원천 API가 아니라 SOOM 공통 모델을 읽도록 설계한다.

Workout import의 표준 흐름은 [SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md](SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md)를 따른다. 이 pipeline은 source fetch, source-specific mapping, `UnifiedWorkout` 생성, data quality evaluation, deduplication, derived input 생성을 분리해 Recovery/Growth/Feed가 정제된 workout만 사용하게 한다.

`UnifiedWorkoutRecord`와 `SwiftDataUnifiedWorkoutStore` v1이 구현되어 `UnifiedWorkout`의 로컬 source of truth 후보가 준비되었다. HealthKit workout은 수동 import preview를 통해 `UnifiedWorkoutStore` 저장까지 연결되었고, Garmin/Samsung import는 아직 future work다. Store는 fuzzy deduplication 없이 `externalId + source` 또는 `id` 기준 upsert만 담당한다.

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

Type-aware analysis v1에서는 `WorkoutGrowthInput.workoutType`이 baseline 분리 기준이다. imported workout source가 달라도 running/cycling/swimming/walking 같은 종목 단위로 비교하고, 서로 다른 종목은 상세 성장 지표 baseline에서 제외한다. 이는 Unified source 확장 이후에도 Growth 해석이 종목별 리듬을 유지하게 하는 기본 계약이다.

## Route and Zone Streams

Workout Map Detail 확장을 위해 Unified source는 summary data뿐 아니라 stream data도 수용할 준비가 필요하다.

후보 stream:

- route coordinates / polyline
- altitude and elevation profile
- heart rate samples
- cycling cadence samples
- cycling power samples
- pace / speed samples
- split or lap summaries

HealthKit에서는 `HKWorkoutRoute`, heart rate, cycling cadence, cycling power가 주요 source 후보이며, Garmin/Samsung/Health Connect도 장기적으로 같은 UnifiedWorkout stream 계약으로 정규화한다. 자세한 지도/zone 설계는 [SOOM_WORKOUT_MAP_DETAIL_EXPERIENCE.md](SOOM_WORKOUT_MAP_DETAIL_EXPERIENCE.md)를 따른다.

Route/Zone Domain Model v1 구현 상태:

- `WorkoutRoute`는 Unified source에서 들어올 route stream을 workout 단위 domain model로 담는 후보다.
- `WorkoutRouteCoordinate`는 route point의 latitude/longitude와 optional altitude/timestamp를 보존한다.
- `WorkoutZone`, `WorkoutZoneSummary`, `WorkoutZoneBuilder`는 heart rate, cadence, power stream을 zone duration/percentage 중심으로 정리하기 위한 순수 모델 계층이다.
- `HealthKitWorkoutRouteFetcher`와 `HealthKitWorkoutRouteMapper`는 `HKWorkoutRoute -> CLLocation stream -> WorkoutRoute` 변환을 구현한다.
- `WorkoutRouteStore`는 route를 workout id 기준으로 저장/조회하는 가벼운 in-memory cache를 제공하고, `PersistedWorkoutRoute`/`SwiftDataWorkoutRoutePersistenceStore`는 local-first route persistence를 담당한다.
- HealthKit heart rate/cadence/power stream query는 `HealthKitWorkoutMetricStreamFetcher`와 `WorkoutZoneDataProvider`를 통해 Workout Detail Zone Cards에 연결되었다. Garmin/Samsung route/stream import는 아직 연결하지 않고 공통 계약만 유지한다.
- RecoveryCalculator와 Workout Growth 계산 로직은 이 모델 추가로 변경되지 않는다.

## WorkoutRoute to Detail Map Overlay

`WorkoutRoute`는 Workout Detail Map Overlay v1에서 route polyline source로 사용된다. Unified route stream이나 HealthKit `HKWorkoutRoute`에서 들어온 좌표는 `WorkoutRoute`로 정규화된 뒤 detail hero map에 표시될 수 있다.

- Detail map은 `WorkoutRoute.coordinates`를 polyline으로 표시한다.
- `WorkoutRoute.bounds`는 route 중심과 camera fitting 후보로 사용한다.
- route가 없거나 token이 없으면 SOOM sport-specific fallback visual을 사용한다.
- Recovery/Growth 계산 입력은 변경하지 않고, map overlay는 visual interpretation layer로만 동작한다.


## Zone Card Connection v1

Heart-rate, cadence, and power streams now have a first UI destination through Workout Detail Zone Cards. v1 uses `WorkoutZoneSummary` and simple distribution bars; HealthKit streams can fill the model at detail time, and future Garmin/Samsung streams can normalize into the same contract once connectors are added.

The connection is intentionally read-only and interpretive. It does not change RecoveryCalculator, Workout Growth scoring, or UnifiedWorkout import policy.

## Metric Stream to Zone Summary Flow

HealthKit metric streams now have a first domain bridge into SOOM zone summaries:

`HKQuantitySample -> HealthKitWorkoutMetricSample -> HealthKitMetricZoneBuilder -> WorkoutZoneSummary`.

Supported v1 stream candidates:

- heart rate samples for Zone 1-5 distribution using Settings maxHR when available, with a fallback max-heart-rate threshold when no user maxHR exists
- cycling cadence samples for low / optimal / high rhythm zones
- cycling power samples using Settings cycling FTP for Zone 1-7 when available, with FTP missing represented as unavailable rather than as an error

This stream path is read-only and interpretive. It connects real HealthKit data to Workout Detail Zone Cards, but does not alter `UnifiedWorkout`, RecoveryCalculator, or Growth score inputs. Garmin/Samsung streams can later normalize into the same metric sample and zone summary contract.


## HR / Cadence / Power Stream to WorkoutZoneSummary

Metric streams now have a direct interpretation path for workout detail zones. HealthKit samples are mapped into SOOM metric samples, then converted into sport-specific `WorkoutZoneSummary` values. Running prioritizes heart-rate zones, cycling can show heart-rate, cadence, and power, swimming keeps heart-rate optional.

The stream path is an interpretation layer for detail UI. It does not modify Recovery score inputs, Growth calculations, import deduplication, or feed sharing behavior.

## UnifiedWorkout externalId as HealthKit Lookup Key

For Apple HealthKit imports, `UnifiedWorkout.externalId` can represent the original `HKWorkout.uuid.uuidString`. Workout detail can use that value to look up the original `HKWorkout` and attach HealthKit metric streams to Zone Cards. Non-HealthKit sources, missing external ids, and lookup failures stay on the existing fallback detail experience.

This keeps `UnifiedWorkout` as the stored summary source while allowing sample-level HealthKit context to be resolved only when the user opens an imported workout detail. RecoveryCalculator, Growth inputs, and deduplication policy are unchanged.

## Zone Source State

Workout Detail Zone Cards distinguish the source state of each `WorkoutZoneSummary`:

- `healthKitStream`: zone distribution came from real HealthKit metric samples.
- `fallbackEstimate`: zone distribution came from existing workout summary/fallback fields.
- `unavailable`: the expected sensor stream is not available for this workout, or cycling FTP is not configured for power zones.
- `manualFuture`: reserved for future user-entered or manually corrected zone data.

This source state helps explain HealthKit stream, fallback, and unavailable behavior without changing the `UnifiedWorkout` import contract, RecoveryCalculator input, or Growth calculations.


## Route / Growth Comparison Inputs

Route Comparison Insight v1 uses existing local domain inputs rather than adding a new external connector.

Flow:

`WorkoutRoute + WorkoutGrowthInput -> RouteSimilarityBuilder -> RouteComparisonCandidate -> WorkoutComparisonInsightBuilder -> WorkoutComparisonInsightCard`

This keeps comparison as an interpretation layer. `WorkoutRoute` supplies approximate route similarity signals such as distance, bounds, and start/end proximity, while `WorkoutGrowthInput` supplies sport-specific metric comparison. UnifiedWorkout, HealthKit, Garmin, Samsung, and SOOM local records can later feed the same route/growth inputs once their route streams are normalized. RecoveryCalculator and Growth calculation logic are not changed by this comparison layer.

## UnifiedWorkoutStore to Comparison Insight

Imported workout detail can now use stored UnifiedWorkout history for comparison candidates:

`UnifiedWorkoutStore -> SimilarWorkoutCandidateProvider -> WorkoutGrowthInput baseline -> WorkoutComparisonInsightBuilder -> WorkoutComparisonInsightCard`

The provider keeps the analysis input boundary clear: it filters out `isExcludedFromAnalysis` workouts, keeps only the same `workoutType`, excludes the current workout, and uses recent records only. Route-based ranking can reuse persisted `WorkoutRoute` values when available; distance/recency fallback is still used when route data is missing. This does not change RecoveryCalculator, Growth builders, deduplication, or import policy.

## Metric Stream to Split Insight

- HealthKit HR/Cadence/Power metric stream은 `WorkoutSplitStreamBuilder`를 통해 time-based split metric으로 변환될 수 있다.
- `WorkoutSplitDataProvider`는 imported workout detail에서 stream 기반 Split Insight를 생성하며, 실패하거나 데이터가 부족하면 기존 heuristic/fallback insight를 유지한다.
- 이 흐름은 운동 상세 해석용이며 RecoveryCalculator, Recovery score, 기존 Growth 계산에는 영향을 주지 않는다.

## Route Similarity to Course Record

Same-course records use the same normalized route/growth boundary as comparison insight:

`WorkoutRoute + WorkoutGrowthInput -> CourseSimilarityBuilder -> CourseRecordBuilder -> CourseRecordCard`

`WorkoutRoute` provides approximate same-course signals such as bounds overlap, start/end proximity, and distance tolerance. `WorkoutGrowthInput` supplies sport-specific metrics such as running pace, cycling speed, swimming 100m pace, distance, and duration. Persisted routes can now be reused by course identity and comparison flows, while imported UnifiedWorkout detail can still fall back to stored same-type candidates through `SimilarWorkoutCandidateProvider` when route data is missing.

This remains an interpretation layer. It does not change RecoveryCalculator, Growth builders, import policy, deduplication, or Feed/SNS behavior.


## Course Identity Foundation v1

`WorkoutRoute` can now be interpreted through `CourseIdentityBuilder` before course record comparison. The generated identity uses normalized bounds, estimated center, distance bucket, and optional direction estimate. Reverse-direction routes are allowed as similar course candidates through `CourseSimilarityBuilder` metadata, but no server identity, GPS map matching, or segment replay is introduced.

This keeps course grouping local-first and future-ready for HealthKit, Garmin, Samsung, and SOOM local routes once their route streams are normalized.


## WorkoutRoute Persistence v1

`WorkoutRoute` now has a local-first SwiftData persistence foundation:

- `PersistedWorkoutRoute` stores route metadata by `workoutId`, source raw value, encoded coordinate payload, coordinate count, distance, elevation gain, timestamps, and a future-ready `courseIdentity` field.
- `WorkoutRouteMapper` converts between `WorkoutRoute` and `PersistedWorkoutRoute` using lightweight JSON coordinate encoding.
- `SwiftDataWorkoutRoutePersistenceStore` handles save/fetch/delete and workout-id upsert. It intentionally does not perform fuzzy deduplication, GIS indexing, server sync, or analysis exclusion.
- HealthKit import can persist a route after `HealthKitWorkout -> UnifiedWorkout -> UnifiedWorkoutStore` succeeds by looking up the original `HKWorkout`, fetching `HKWorkoutRoute`, and saving the mapped `WorkoutRoute`. Route failures are ignored so workout import remains safe.

This gives CourseIdentity, CourseRecord, and Route Comparison a reusable local route source without changing RecoveryCalculator, Growth builders, Garmin/Samsung connectors, or server/Auth policy.

### Persisted Route Reuse v1

`PersistedRouteCandidateProvider` now reads the current workout route and recent candidate routes from `SwiftDataWorkoutRoutePersistenceStore` for comparison flows. `SimilarWorkoutCandidateProvider` can use those persisted routes with `RouteSimilarityBuilder` before falling back to distance/recency matching. Route lookup failures are treated as non-blocking so imported workout detail can still render comparison and course record fallback states.

## Persisted Route / Course Identity to Progression

Persisted route context can now support course progression in addition to comparison and course record. Imported workout detail can reuse `PersistedRouteCandidateProvider` output through `SimilarWorkoutCandidateProvider`, then pass candidate workouts, route candidates, and current Course Identity into `CourseProgressionBuilder`.

Flow:

`PersistedWorkoutRoute -> PersistedRouteCandidateProvider -> SimilarWorkoutCandidateResult -> CourseProgressionBuilder -> CourseProgressionCard`

If persisted route data is unavailable or lookup fails, the progression layer falls back to same-type workout history and can show an insufficient-data state. This does not change RecoveryCalculator, Growth builders, import deduplication, Feed/SNS, or server/Auth policy.

## Route Elevation to Climb Insight

Route elevation and workout summary fields can now feed a terrain interpretation layer:

`WorkoutRoute + WorkoutGrowthInput + optional split metrics -> ClimbInsightBuilder -> ClimbInsightCard`

This is used for cycling and hiking detail views when elevation gain is meaningful. Imported UnifiedWorkout detail can now read the persisted `WorkoutRoute` by `workoutId` through `WorkoutDetailRouteContextProvider` and pass that route into `ClimbInsightBuilder`, making stored route elevation/profile the preferred terrain source. If persisted route lookup fails or route elevation is unavailable, the builder falls back to `WorkoutGrowthInput.elevationGainMeters`; if elevation is too low or missing, the card stays hidden. This does not change RecoveryCalculator, Growth builders, import deduplication, Feed/SNS, or server/Auth policy.

## Route / Elevation / Split to Terrain Context

`WorkoutRoute`, `WorkoutGrowthInput`, and optional `WorkoutSplitMetric` can now feed terrain classification before detail interpretation cards are shown.

Flow:

`WorkoutRoute + WorkoutGrowthInput + optional split metrics -> TerrainTypeBuilder -> TerrainInsightBuilder -> TerrainInsightCue`

Persisted route distance and elevation are preferred when available, while workout summary distance/elevation provides fallback. The resulting terrain context can help Climb Insight, Split Rhythm, and Course Progression read the workout as flat, rolling, climb-heavy, trail-like, or mixed without changing RecoveryCalculator, Growth builders, import policy, Feed/SNS, or server/Auth behavior.

Split-metric based terrain classification is currently a future-ready foundation. It can identify conservative urban stop-go style rhythm when enough split speed variation exists, but advanced stop detection, GPS replay, and precision terrain classification are still deferred.

## Aggregated Workout Interpretation Layer

Unified workout records can now feed long-term progression interpretation after they are converted into `WorkoutGrowthInput`:

`UnifiedWorkoutStore -> UnifiedWorkoutAnalysisInputSelector -> WorkoutGrowthInput[] -> ProgressionIntelligenceBuilder -> ProgressionIntelligenceCard`

The layer aggregates recent included workouts and interprets pace, speed, rhythm stability, and training frequency over weekly/monthly windows. It is local-first and does not change RecoveryCalculator, existing Growth builders, Feed/SNS, server/Auth, Garmin/Samsung, or ML policy.

## Future User Ownership Boundary

SOOM now has a local-first `AppUser` / `AuthSession` foundation. Current workout, route, settings, and HealthKit-derived records remain local to the device, but future persistence can migrate toward user-scoped ownership.

Future direction:

`AppUser.id -> user-scoped settings / workouts / routes / share defaults`

The v1 foundation does not add `user_id` to existing SwiftData schemas, does not sync to a server, and does not change import, RecoveryCalculator, Growth builders, route persistence, or Feed/SNS behavior. `UserScopedStorageKey` exists only as a lightweight namespace helper for future migration.

## Supabase Auth Preparation Boundary

Auth now has a repository boundary on top of the local session store:

`AuthViewModel -> AuthRepository -> LocalAuthRepository -> AuthSessionStore`

`SupabaseAuthConfiguration`, `SupabaseClientProvider`, and `SupabaseAuthProvider` now form the remote-auth boundary. The Supabase SDK is installed, and Apple Sign In can exchange an Apple ID token for a Supabase Auth session when the environment is configured. Server storage, Google/password auth, and local workout ownership migration remain deferred. HealthKit, workout, route, and progression records are not moved to a server. Future `user_id` ownership can attach behind this boundary without forcing schema changes in v1.
## Auth Environment Foundation

`AuthEnvironmentLoader` can read Supabase and redirect placeholders from Info.plist, but placeholder values are treated as unconfigured. This prepares future user ownership without changing local-first HealthKit import, route persistence, workout analysis, RecoveryCalculator, Growth builders, or Feed/SNS behavior.

Secrets must come from Xcode build settings, ignored `.xcconfig` files, or CI secret injection in a later phase. No real Supabase URL, anon key, or OAuth redirect value should be committed.


## Supabase SDK Integration Boundary

The Supabase Swift SDK is now available behind `SupabaseClientProvider`, but HealthKit-derived workouts, routes, zones, progression intelligence, and local user data remain local-first. `SupabaseClientProvider` can create a client only from configured environment values; it does not upload records, migrate schemas, assign remote `user_id` ownership, or change RecoveryCalculator, Growth, Workout, Feed, or HealthKit import behavior.


## Supabase Session Smoke Boundary

Supabase auth session smoke is read-only and separate from data ownership.

Flow:

`AuthEnvironment -> SupabaseClientProvider -> SupabaseAuthSessionProbe -> SupabaseAuthSessionSnapshot`

A signed-in Supabase snapshot with a valid UUID user id can now be bridged into a transient `AppUser` / `AuthSession.signedIn` state for Settings/My Page. It still does not migrate local HealthKit/workout data, attach `user_id` to SwiftData schemas, upload routes/zones/progression records, or replace the local `AuthSessionStore`. Missing configuration, missing session, or lookup failure all preserve local-first behavior.


## Email Auth Request Boundary

Supabase email magic link/OTP request is now available as an auth UI foundation, but it is separate from data ownership.

Flow:

`Settings/My Page -> EmailAuthViewModel -> SupabaseAuthProvider.requestMagicLink -> Supabase Auth OTP request`

This flow does not replace the local `AuthSessionStore`, does not attach remote `user_id` to SwiftData records, does not sync HealthKit/workout/route/progression data, and does not change RecoveryCalculator or Growth builders. The remote session bridge is available for account-connected UI state after Apple sign-in or session checks, while explicit data ownership migration remains a future step.


## Supabase Session Bridge Boundary

`SupabaseAuthSessionSnapshot -> SupabaseAppUserMapper -> AuthSessionBridge -> AuthViewModel.checkRemoteSession()` can represent an existing Supabase current session with a valid UUID user id as an account-connected UI state. This is intentionally separate from local data ownership: no SwiftData schema receives `user_id`, no HealthKit/workout/route/progression record is uploaded, and local-first fallback remains intact when remote session lookup fails.


## Apple Sign In Account Boundary

Apple Sign In can now create a Supabase Auth session through an Apple ID token exchange when the app entitlement and Supabase environment are configured. The resulting remote account session is still separate from local workout ownership: no HealthKit, route, workout, zone, progression, Feed, or Recovery data is migrated to a remote `user_id`, and no SwiftData schema receives user ownership fields in this step.

If Apple credential parsing, Supabase configuration, network exchange, or session bridging fails, SOOM preserves the local-first session and local data remains on device. Explicit ownership migration and remote sync remain future work.


## Email Callback Session Boundary

Email Magic Link callback handling can now validate `auth/callback` URLs and ask Supabase Auth to load a session from the callback URL. If a valid Supabase session is available, the existing session bridge can represent it as account-connected UI state. This remains separate from local workout ownership: no HealthKit, workout, route, zone, progression, Feed, Recovery, or Growth data is migrated or uploaded, and no SwiftData schema receives remote `user_id` fields in this step.

## Supabase Session Restore Boundary

App launch session restore can now represent an existing Supabase `currentSession` as account-connected UI state. This is a read-only auth-state restore, not a data ownership migration. Local workout, route, HealthKit, zone, progression, Feed, Recovery, and Growth records are not assigned a remote `user_id`, uploaded, or synced as part of this step.


## Root Auth Bootstrap Boundary

Session restore is now orchestrated from the app bootstrap layer. `SOOMApp` creates the shared auth view model, runs `RootAuthBootstrap`, and passes the resulting auth state through the SwiftUI environment before Settings is opened. This keeps account state global while preserving the same local-first data boundary: remote account visibility still does not create user-scoped workout ownership, HealthKit sync, route sync, Feed sync, Recovery sync, or Growth sync.


## Magic Link Callback Root State Boundary

Email Magic Link callbacks can now update the shared root auth view model as soon as a valid Supabase session is bridged. This is still only account UI state. Local HealthKit, workout, route, zone, progression, Feed, Recovery, and Growth records are not assigned a remote `user_id`, uploaded, migrated, or synced by the callback result.

## Production Redirect Boundary

Email Magic Link device QA now has a concrete native callback target: `soom-auth://auth/callback`, registered through `CFBundleURLTypes` and backed by the `SOOM_AUTH_REDIRECT_SCHEME` build setting. This only enables the app to receive auth callbacks. It does not migrate local HealthKit, workout, route, zone, progression, Feed, Recovery, or Growth data to remote ownership, and it does not add `user_id` to local schemas.
