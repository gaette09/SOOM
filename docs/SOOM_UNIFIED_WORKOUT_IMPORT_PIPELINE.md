# SOOM Unified Workout Import Pipeline v1

## A. Purpose

SOOM은 Apple HealthKit, Garmin, Samsung Health, Health Connect, SOOM local/manual 기록처럼 여러 source에서 운동 데이터를 받을 수 있다. Unified Workout Import Pipeline의 목적은 source별 운동 데이터를 바로 Recovery, Growth, Feed에 넘기지 않고, SOOM이 이해하는 공통 구조로 정제한 뒤 품질, 중복, 사용자 수정 우선순위를 확인하는 표준 흐름을 만드는 것이다.

이 pipeline은 다음 문제를 줄인다.

- source별 단위와 필드 차이
- HealthKit/Garmin/Samsung 간 중복 운동
- 누락 metric 또는 추정 metric의 불명확성
- Recovery/Growth 계산에서 같은 운동이 두 번 합산되는 문제
- Feed/SNS에 같은 운동 카드가 반복 노출되는 문제

원칙:

- source-specific model은 import 경계에서만 다룬다.
- 앱 내부 계산과 화면은 `UnifiedWorkout` 또는 그 파생 입력을 기준으로 한다.
- Recovery/Growth/Feed 계산 전에는 data quality와 deduplication 상태를 확인한다.
- v1은 자동 삭제/자동 병합을 하지 않는다.

## B. Pipeline Stages

권장 import pipeline 단계:

1. **Source Fetch**
   - HealthKit, Garmin, Samsung Health, Health Connect, SOOM local/manual source에서 원천 workout을 가져온다.
   - 권한 거부, source fetch 실패, 빈 데이터는 앱 전체 실패로 전파하지 않는다.

2. **Source-specific Mapping**
   - source별 원천 모델을 SOOM 내부 source snapshot으로 변환한다.
   - 예: `HKWorkout -> HealthKitWorkout`
   - Garmin/Samsung은 향후 source-specific snapshot 또는 DTO를 둔다.

3. **UnifiedWorkout Creation**
   - source snapshot을 `UnifiedWorkout`으로 변환한다.
   - 단위는 공통 기준으로 정리한다. 거리 meter, 시간 seconds, energy kcal, heart rate bpm.

4. **Data Quality Evaluation**
   - 누락 필드, 추정 필드, source confidence를 평가한다.
   - `UnifiedDataQuality` 또는 향후 quality metadata에 반영한다.

5. **Deduplication Candidate Detection**
   - `UnifiedWorkoutDeduplicationEngine`으로 중복 후보를 찾는다.
   - 이 단계는 `RecoveryActivity` 또는 `WorkoutGrowthInput` 생성 전이어야 한다.

6. **User/Edit Priority Resolution**
   - manual / SOOM local / user-edited 기록을 imported data보다 신중하게 우선한다.
   - v1은 자동 삭제가 아니라 primary 후보 선택과 review 후보 분리를 목표로 한다.

7. **Store / Snapshot**
   - 정제된 `UnifiedWorkout`과 import metadata를 저장하는 단계다.
   - `UnifiedWorkoutRecord`와 `SwiftDataUnifiedWorkoutStore` v1이 준비되어 있으며, HealthKit import preview는 `HealthKitWorkout`을 `UnifiedWorkout`으로 변환한 뒤 Store에 저장하는 흐름까지 연결되어 있다.
   - Store는 fuzzy deduplication을 하지 않고 `externalId + source` 또는 `id` 기준 upsert만 담당한다.

8. **Derived Inputs 생성**
   - Recovery: deduped primary `UnifiedWorkout` collection -> `RecoveryActivity`
   - Workout Growth: deduped primary `UnifiedWorkout` collection -> `WorkoutGrowthInput`
   - Feed: deduped primary `UnifiedWorkout` -> FeedCard 후보

9. **UI Refresh**
   - Recovery, Analysis/Growth, Feed가 새 derived input 또는 snapshot을 기준으로 refresh된다.
   - import 실패가 UI 전체 실패로 이어지지 않게 partial state를 허용한다.

## C. Source-specific Examples

### Apple HealthKit

```text
HKWorkout
-> HealthKitWorkout
-> HealthKitWorkoutToUnifiedWorkoutMapper
-> UnifiedWorkout
```

현재 SOOM에는 `HealthKitWorkout`과 `HealthKitWorkoutToUnifiedWorkoutMapper`가 준비되어 있다. HealthKit은 source 중 하나일 뿐이며, Recovery 기본 source로 바로 전환하지 않는다.

### Garmin Activity

```text
Garmin Activity API payload
-> GarminWorkoutSnapshot 후보
-> GarminWorkoutToUnifiedWorkoutMapper 후보
-> UnifiedWorkout
```

Garmin은 cycling/running에서 power, cadence, lap, route 등 sport-specific metric이 풍부할 수 있다. 향후 source priority에서 Garmin 원본 workout이 HealthKit aggregator copy보다 primary가 될 수 있다.

### Samsung Health / Health Connect

```text
Samsung Health Exercise 또는 Health Connect ExerciseSession
-> SamsungWorkoutSnapshot 후보
-> SamsungWorkoutToUnifiedWorkoutMapper 후보
-> UnifiedWorkout
```

Samsung/Health Connect는 iOS 앱에서 직접 다루기보다 서버/계정 동기화 후보로 검토한다. v1에서는 문서와 공통 모델 수용 범위만 정의한다.

### SOOM Manual / Local Workout

```text
SOOM manual workout 또는 LocalWorkoutSnapshot
-> SOOMLocalWorkoutToUnifiedWorkoutMapper 후보
-> UnifiedWorkout
```

SOOM manual 기록은 사용자가 직접 입력하거나 수정한 데이터로 볼 수 있으므로, imported source보다 조심스럽게 우선한다. user edit wins over imported data 원칙을 따른다.

## D. Deduplication Placement

Deduplication은 `UnifiedWorkout` 생성 이후, `RecoveryActivity` / `WorkoutGrowthInput` / FeedCard 후보 생성 전에 수행한다.

권장 위치:

```text
Source Fetch
-> Source-specific Mapping
-> UnifiedWorkout Creation
-> Data Quality Evaluation
-> Deduplication Candidate Detection
-> User/Edit Priority Resolution
-> Derived Inputs
```

v1 정책:

- `UnifiedWorkoutDeduplicationEngine`은 중복 후보만 반환한다.
- 자동 삭제/자동 병합은 하지 않는다.
- confidence가 높은 후보는 primary workout만 계산 입력에 사용하도록 준비한다.
- confidence가 낮거나 manual record와 충돌하면 user review 후보로 둔다.
- 원본 source record와 duplicate candidate relationship은 보존한다.

Deduplication 세부 정책은 [SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md](SOOM_UNIFIED_WORKOUT_DEDUPLICATION.md)를 따른다.

## E. Storage Strategy

v1 저장 후보:

### UnifiedWorkoutRecord

SwiftData v1 구현 필드:

- `id`
- `externalId`
- `sourceRaw`
- `workoutTypeRaw`
- `startDate`
- `endDate`
- `durationSeconds`
- `distanceMeters`
- `activeEnergyKcal`
- `averageHeartRate`
- `maxHeartRate`
- `averageSpeedMetersPerSecond`
- `elevationGainMeters`
- `dataQuality`
- `syncTimestamp`
- `createdAt`
- `updatedAt`
- `isExcludedFromAnalysis`

### UnifiedWorkoutStore v1

`SwiftDataUnifiedWorkoutStore`는 `UnifiedWorkout`의 로컬 source of truth 후보로 준비되었다. 현재 역할은 저장/조회/upsert/분석 제외 표시이며, HealthKit import preview에서는 `HealthKitWorkout` -> `UnifiedWorkout` -> `UnifiedWorkoutStore` 저장 흐름까지 연결되어 있다. 다만 저장된 workout은 아직 `RecoveryActivity` / `WorkoutGrowthInput` derived input 생성에 자동 연결하지 않으며, `UnifiedWorkoutDeduplicationEngine`도 import pipeline에 자동 적용하지 않는다.

지원 API:

- `saveWorkout(_:)`
- `saveWorkouts(_:)`
- `fetchRecentWorkouts(days:)`
- `fetchWorkout(id:)`
- `fetchByExternalId(_:source:)`
- `markExcludedFromAnalysis(id:isExcluded:)`
- `deleteWorkout(id:)`

Upsert 정책:

- `externalId + source`가 있으면 같은 원천 운동으로 보고 upsert한다.
- `externalId`가 없으면 `id` 기준으로 upsert한다.
- 시간/거리/운동 타입 유사도 기반 fuzzy deduplication은 Store 책임이 아니라 `UnifiedWorkoutDeduplicationEngine` 책임이다.
- `isExcludedFromAnalysis`는 중복 후보 검토 또는 사용자가 분석 제외로 둔 기록을 보존하기 위한 flag이며, 삭제를 의미하지 않는다.

### Imported UnifiedWorkout Library / Duplicate Review

HealthKit import preview로 저장된 `UnifiedWorkout`은 Library 화면에서 최근 30일 기준으로 확인할 수 있다. Library는 운동 타입, source, 날짜, 시간, 거리, duration, dataQuality, `isExcludedFromAnalysis` 상태를 보여주는 관리/검토 영역이다.

Library에서 `UnifiedWorkoutDuplicateReviewView`로 이동하면 저장된 workout 중 중복 후보를 확인할 수 있다. Review는 `UnifiedWorkoutDeduplicationEngine`을 사용해 confidence, reasons, preferredSource, resolutionPolicy를 표시하지만 자동 삭제/자동 병합/자동 분석 제외는 수행하지 않는다.

Library에서는 사용자가 개별 workout을 수동으로 “분석 제외” 또는 “분석 포함” 상태로 바꿀 수 있다. 이 동작은 `SwiftDataUnifiedWorkoutStore.markExcludedFromAnalysis(id:isExcluded:)`를 호출해 `isExcludedFromAnalysis` flag만 변경하며, 원본 workout을 삭제하거나 병합하지 않는다.

분석 제외 정책:

- 제외된 workout은 향후 Recovery/Growth derived input 생성 단계에서 계산 후보에서 빠질 수 있다.
- v1에서는 RecoveryActivity / WorkoutGrowthInput 생성 흐름에 아직 연결하지 않는다.
- 중복 후보 Review는 자동 제외를 수행하지 않고, 사용자가 Library에서 직접 제외 여부를 정한다.
- 분석 제외는 데이터 삭제가 아니며 언제든 다시 포함할 수 있는 상태 flag다.

현재 import pipeline의 범위:

- HealthKit workout을 `UnifiedWorkoutStore`에 저장
- 저장된 workout을 Library에서 확인
- 저장된 workout의 중복 후보를 Review에서 확인
- 저장된 workout을 사용자가 수동으로 분석 제외/포함 상태로 변경
- RecoveryActivity / WorkoutGrowthInput / FeedCard 생성은 아직 연결하지 않음

### Analysis Input Selector v1

`UnifiedWorkoutAnalysisInputSelector`는 저장된 `UnifiedWorkout` 배열에서 `isExcludedFromAnalysis == true`인 workout을 제거한 뒤 분석 입력을 만드는 순수 selector다.

지원 역할:

- `selectIncludedWorkouts(_:)`: 분석 대상 workout만 반환한다.
- `selectRecoveryInputs(from:)`: 포함 대상 workout만 `UnifiedWorkoutToRecoveryActivityMapper`로 `RecoveryActivity`로 변환한다.
- `selectGrowthInputs(from:)`: 포함 대상 workout만 `UnifiedWorkoutToGrowthInputMapper`로 `WorkoutGrowthInput`으로 변환한다.

정책:

- 원본 workout 순서는 그대로 유지한다.
- Recovery/Growth 실제 화면 흐름에는 아직 자동 연결하지 않는다.
- `RecoveryCalculator`, `WorkoutGrowthSummaryBuilder`, `WorkoutWeaknessInsightBuilder`를 직접 호출하지 않는다.
- DeduplicationEngine 자동 적용은 하지 않는다.
- 향후 dedup review에서 사용자가 특정 중복 후보를 분석 제외로 표시하면, derived input 생성 전 이 selector가 제외 상태를 반영할 수 있다.

### Raw Source Payload

raw payload 저장은 신중히 검토한다.

장점:

- mapper 개선 시 재처리 가능
- source-specific detail 보존 가능

단점:

- 건강 데이터 민감도 증가
- 저장 공간 증가
- privacy/delete 정책 복잡도 증가

v1 추천:

- summary-level `UnifiedWorkoutRecord` 우선
- raw payload는 저장하지 않거나 debug/import audit 전용으로 제한
- externalId, source, sync timestamp는 필수 후보

## F. Error / Missing Data Strategy

source별 실패와 누락 데이터는 사용자 경험을 막지 않는 방식으로 처리한다.

### Metric 누락

- average heart rate가 없으면 training load 추정 confidence를 낮춘다.
- distance가 없으면 distance 기반 Growth metric은 표시하지 않거나 partial로 둔다.
- calories가 없으면 active energy 기반 추정은 하지 않는다.

### 권한 거부

- 해당 source를 unavailable/denied 상태로 표시한다.
- 다른 source가 있으면 pipeline은 계속 진행한다.
- 사용자를 탓하지 않는 copy를 사용한다.

### Source Fetch 실패

- 실패 source만 제외하고 성공 source를 처리한다.
- 반복 실패는 sync status에 기록한다.
- Recovery/Growth는 가능한 데이터로 partial interpretation을 유지한다.

### Partial / Estimated Data

- `UnifiedDataQuality.partial` 또는 `estimated`로 표시한다.
- estimated field는 향후 confidence score와 사용자 설명에 반영한다.

## G. Safety Policy

SOOM import pipeline safety policy:

- 사용자 데이터 자동 삭제 금지
- imported source보다 manual edit / user-owned correction 우선
- 중복 후보는 삭제가 아니라 계산 제외 또는 검토 후보
- Recovery/Growth 계산에는 deduped primary workout input 사용
- Feed/SNS에는 같은 운동 카드가 반복 노출되지 않게 primary candidate 사용
- HealthKit/Garmin/Samsung source 연결은 read-first 정책 유지
- 서버 동기화 또는 raw payload 저장은 별도 동의 필요

## H. Future Implementation Plan

Phase 1: 문서화. 현재 단계.

- source별 import 흐름 정의
- deduplication 위치 정의
- storage/error/safety policy 정의

Phase 2: UnifiedWorkoutStore 설계

- `UnifiedWorkoutRecord` 후보 구체화
- raw payload 저장 여부 결정
- import sync metadata 설계

Phase 3: ImportPipeline 모델/프로토콜

- `UnifiedWorkoutSource`
- `UnifiedWorkoutImporter`
- `UnifiedWorkoutImportPipeline`
- `UnifiedWorkoutImportResult`

Phase 4: HealthKit pipeline 연결

- `HealthKitWorkoutFetcher`
- `HealthKitWorkoutToUnifiedWorkoutMapper`
- `UnifiedWorkoutStore`
- 아직 Recovery 기본 source 전환은 별도 결정
- 구현 상태: `HealthKitWorkoutImportPipeline`이 HealthKit workout fetch, `UnifiedWorkout` 변환, `UnifiedWorkoutStore` 저장까지 수행한다.
- import 결과는 `HealthKitWorkoutImportResult`로 fetched/saved/skipped/failed count와 message를 반환한다.
- 현재 범위는 UnifiedWorkoutStore 저장까지만이며, RecoveryActivity / WorkoutGrowthInput derived input 생성은 하지 않는다.

Phase 5: Deduplication 적용

- `UnifiedWorkoutDeduplicationEngine`을 import pipeline 중간 단계에 연결
- candidate 저장 또는 primary selection 정책 구현
- 자동 삭제/자동 병합은 계속 금지

Phase 6: Recovery/Growth derived input 생성

- deduped primary `UnifiedWorkout` -> `RecoveryActivity`
- deduped primary `UnifiedWorkout` -> `WorkoutGrowthInput`
- 기존 `RecoveryCalculator`와 Growth Builder 공식은 그대로 유지

Phase 7: Feed card 생성

- deduped primary `UnifiedWorkout` -> Feed card 후보
- 중복 운동 카드 반복 노출 방지
- 사용자 공유/비공개 정책 반영

## Current Boundary

현재 HealthKit import pipeline v1에서는 다음을 하지 않는다.

- DeduplicationEngine 자동 적용
- DeduplicationEngine 연결
- RecoveryActivity 생성 흐름 변경
- WorkoutGrowthInput 생성 흐름 변경
- Garmin/Samsung 실제 연동
- Recovery 기본 source 전환
- Feed/SNS 기능 구현

## HealthKit Import Pipeline v1

구현된 흐름:

1. `HealthKitWorkoutFetching`에서 최근 workout을 가져온다.
2. `HealthKitWorkoutToUnifiedWorkoutMapper`가 `UnifiedWorkout`으로 변환한다.
3. `UnifiedWorkoutStore.saveWorkouts(_:)`로 로컬 저장소에 저장한다.
4. `HealthKitWorkoutImportResult`로 import 요약을 반환한다.

정책:

- fetch 실패는 앱 전체 실패로 전파하지 않고 failed result로 반환한다.
- 저장 실패는 fetched count를 유지한 failed result로 반환한다.
- 같은 `externalId + source` 재import 중복 처리는 `UnifiedWorkoutStore`의 upsert 정책에 맡긴다.
- fuzzy deduplication은 이 단계에 자동 적용하지 않는다.
- Recovery/Growth 계산 입력 생성은 후속 단계에서 deduped primary workout을 기준으로 별도 연결한다.

## HealthKit Workout Import Preview MVP

수동 import preview UI를 통해 사용자는 HealthKit workout을 SOOM의 `UnifiedWorkoutStore`로 가져오고 결과를 확인할 수 있다.

표시 범위:

- fetchedCount
- savedCount
- skippedCount
- failedCount
- import message

정책:

- import UI는 HealthKit 설정/관리 영역에만 둔다.
- 가져온 `UnifiedWorkout`은 아직 RecoveryActivity 또는 WorkoutGrowthInput으로 자동 파생하지 않는다.
- DeduplicationEngine은 자동 적용하지 않는다.
- 중복 저장 방지는 store의 `externalId + source` upsert 정책에만 의존한다.
- 복잡한 import history UI는 만들지 않고, 마지막 import 결과만 보여준다.

## Imported UnifiedWorkout Library MVP

가져온 운동 기록은 `UnifiedWorkoutLibraryView`에서 최근 30일 목록으로 확인할 수 있다. 이 화면은 HealthKit 설정/관리 영역에 있으며, Recovery 핵심 화면이나 운동 상세 화면과 분리한다.

표시 범위:

- 운동 타입
- source
- 날짜와 시간
- 거리와 duration
- dataQuality
- `isExcludedFromAnalysis` 상태

정책:

- Library는 저장된 `UnifiedWorkoutStore` 내용을 검토하는 관리 화면이다.
- 이 목록은 아직 RecoveryActivity 또는 WorkoutGrowthInput을 자동 생성하지 않는다.
- DeduplicationEngine은 자동 적용하지 않는다.
- 편집/삭제 UI는 제공하지 않는다.
- 가져온 기록이 분석 후보인지, 분석 제외 상태인지 확인하는 용도로만 사용한다.

## UnifiedWorkout -> Weekly Workout Progress 연결 v1

Imported `UnifiedWorkout`은 `UnifiedWorkoutStore`에서 조회된 뒤 `UnifiedWorkoutAnalysisInputSelector`를 거쳐 `WorkoutGrowthInput`으로 변환되고, `WeeklyWorkoutProgressBuilder`의 주간 성장 요약 입력으로 사용할 수 있다. 이는 HealthKit으로 가져온 workout이 Growth analysis에 반영되는 첫 연결이다. RecoveryActivity 생성, RecoveryCalculator 입력, DeduplicationEngine 자동 적용은 아직 연결하지 않는다.

