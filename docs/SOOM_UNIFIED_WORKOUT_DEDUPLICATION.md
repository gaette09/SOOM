# SOOM Unified Workout Deduplication v1

## A. Purpose

SOOM은 Apple HealthKit, Garmin, Samsung Health, Health Connect, SOOM 자체 기록처럼 여러 source에서 운동 데이터를 가져올 수 있다. 이 구조에서는 같은 운동이 두 번 이상 들어올 가능성이 높다.

예를 들어 Garmin으로 기록한 라이딩이 Apple HealthKit에 자동 동기화되면, SOOM은 Garmin workout과 HealthKit workout을 서로 다른 운동처럼 볼 수 있다. 이 중복이 그대로 Recovery, Workout Growth, Feed/SNS에 들어가면 사용자는 실제보다 더 많이 운동한 것처럼 보이고, 회복 점수나 주간 성장 흐름도 과장될 수 있다.

Deduplication의 목적은 원본 데이터를 삭제하는 것이 아니라, 같은 운동으로 보이는 기록을 감지하고 SOOM 계산/표시 계층에서 한 번만 사용하도록 안전한 기준을 만드는 것이다.

Deduplication은 독립 실행 단계가 아니라 [SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md](SOOM_UNIFIED_WORKOUT_IMPORT_PIPELINE.md)의 중간 단계다. source별 workout이 `UnifiedWorkout`으로 정제된 뒤, `RecoveryActivity`, `WorkoutGrowthInput`, FeedCard 후보를 만들기 전에 중복 후보를 감지한다.

`SwiftDataUnifiedWorkoutStore` v1은 `UnifiedWorkout` 저장/조회/upsert만 담당하며 fuzzy deduplication을 수행하지 않는다. Store의 upsert는 `externalId + source` 또는 `id` 기준으로만 동작하고, 시작 시간/거리/운동 타입 유사도 판단은 `UnifiedWorkoutDeduplicationEngine` 책임으로 분리한다.

## B. Duplicate Scenarios

SOOM에서 예상하는 중복 시나리오:

- Garmin 라이딩이 Garmin Activity API와 Apple HealthKit 양쪽에서 들어옴
- Apple Watch와 Garmin을 동시에 착용하고 같은 러닝을 기록함
- Samsung Health와 Health Connect가 같은 운동을 공유함
- Strava 같은 외부 앱이 HealthKit에 운동을 쓰고, SOOM이 원본 source와 HealthKit 집계본을 함께 읽음
- SOOM 수동 기록과 외부 기기 기록의 시간이 겹침
- 같은 운동을 나중에 사용자가 직접 수정해 source별 값이 조금 다르게 남음

중복이 생기면:

- Recovery 계산에서 training load가 두 번 더해질 수 있다.
- Workout Growth에서 주간 거리/시간/횟수가 과장될 수 있다.
- Feed/SNS에 같은 운동 카드가 여러 번 보일 수 있다.
- AI Coach가 실제보다 피로 누적이 크다고 해석할 수 있다.

## C. Matching Signals

중복 후보 판단에 사용할 signal:

- `externalId`
- `source`
- `startDate`
- `endDate`
- `duration`
- `distance`
- `workoutType`
- average / max heart rate summary
- route 또는 polyline 유사도 후보
- device id 또는 source bundle id
- source priority
- sync timestamp
- user-edited 여부

v1에서는 summary-level signal을 우선 사용한다. route/polyline, lap, stream 기반 matching은 v2 이후로 둔다.

## D. v1 Deduplication Policy

v1 추천 정책:

- 같은 `externalId`와 같은 `source`이면 같은 workout으로 본다.
- source가 달라도 시작 시간이 ±2~5분 이내이고, 운동 타입이 같으면 중복 후보로 본다.
- duration 차이가 5% 미만이면 confidence를 높인다.
- distance 차이가 5~10% 미만이면 confidence를 높인다.
- heart rate summary가 유사하면 보조 signal로 사용한다.
- route/polyline이 있으면 장기적으로 가장 강한 signal 중 하나로 사용한다.
- 최종 판단은 confidence score 기반으로 한다.

Confidence 예시:

- 0.90 이상: 자동 병합 후보
- 0.70~0.89: 중복 가능성이 높은 후보
- 0.50~0.69: 사용자 확인 후보
- 0.50 미만: 별도 운동으로 유지

v1에서는 자동 삭제하지 않는다. import pipeline이나 계산 입력에서 primary workout만 선택해 중복 합산을 피하는 방향으로 시작한다.

## E. Source Priority

Source priority는 “무조건 어떤 source가 우선”이 아니라 종목/데이터 풍부도/사용자 수정 여부를 함께 본다.

우선순위 후보:

- Garmin cycling/running workout은 power, cadence, lap, route 등 스포츠 지표가 풍부할 수 있으므로 원본 source로 우선할 수 있다.
- Apple HealthKit은 iOS system aggregator로 안정적이지만, 외부 source에서 들어온 복사본일 수 있다.
- Samsung Health / Health Connect는 Android source와 서버 동기화에서 중요해질 수 있다.
- SOOM manual entry는 사용자가 직접 수정한 기록이므로 user-owned correction으로 다룬다.
- 사용자가 수정한 데이터는 imported data보다 우선한다.

정책:

- user edit wins over imported data.
- sport-specific richer source can become primary.
- HealthKit aggregator copy should not automatically override original device source.
- source priority는 투명해야 하며, 나중에 사용자에게 “왜 이 기록을 대표 기록으로 골랐는지” 설명할 수 있어야 한다.

## F. UnifiedWorkoutDuplicateCandidate Model Candidate

향후 모델 후보:

```swift
struct UnifiedWorkoutDuplicateCandidate {
    let primaryWorkout: UnifiedWorkout
    let duplicateWorkout: UnifiedWorkout
    let confidence: Double
    let reasons: [String]
    let preferredSource: UnifiedDataSource
    let resolutionPolicy: UnifiedWorkoutDuplicateResolutionPolicy
}
```

Resolution policy 후보:

- `keepPrimary`
- `mergeMetrics`
- `needsUserReview`
- `keepBoth`
- `ignoreCandidate`

Candidate reason 예시:

- “시작 시간이 2분 이내로 유사함”
- “운동 시간이 3% 이내로 유사함”
- “거리 차이가 5% 이내”
- “같은 cycling workout type”
- “Garmin 원본과 HealthKit 동기화본으로 추정”

## G. Safety Policy

SOOM v1 safety policy:

- 자동 삭제 금지
- 원본 workout record는 보존
- 중복 후보 표시 또는 내부 병합 후보로만 다룸
- Recovery/Growth 계산에서는 중복 합산 방지가 중요
- Feed/SNS에서는 같은 운동 카드가 반복 노출되지 않게 primary workout만 표시 후보로 사용
- 사용자 데이터 삭제는 명시적 동의가 있을 때만 수행
- 중복 판단 confidence가 낮으면 별도 운동으로 유지
- 수동 기록 또는 사용자 수정 기록은 외부 import보다 조심스럽게 다룸

Recovery와 Growth는 source별 raw data가 아니라 deduplicated `UnifiedWorkout` collection을 입력으로 받는 방향을 목표로 한다.

## H. Future Implementation Plan

Phase 1: 문서화. 현재 단계.

- 중복 시나리오 정의
- matching signal 정의
- source priority와 safety policy 정의

Phase 2: DuplicateCandidate 모델

- `UnifiedWorkoutDuplicateCandidate`
- `UnifiedWorkoutDuplicateResolutionPolicy`
- confidence reason 모델

Phase 3: DeduplicationEngine 테스트

- externalId match
- time/duration/distance fuzzy match
- source priority
- low confidence safety
- `UnifiedWorkoutDeduplicationEngine` 순수 로직 구현 완료
- `UnifiedWorkoutDuplicateCandidate` 모델 구현 완료
- 아직 import pipeline에는 연결하지 않음
- 자동 삭제/자동 병합은 수행하지 않음

Phase 4: import pipeline에서 중복 제외

- HealthKit/Garmin/Samsung import 결과를 `UnifiedWorkout`으로 모은 뒤 중복 후보 감지
- Recovery/Growth 계산 전 primary workout collection 생성

Phase 5: 사용자 확인 UI

- 중복 가능성이 낮거나 수동 기록과 충돌하는 경우 사용자 확인
- 삭제가 아니라 “대표 기록 선택” 중심 UX

## Current Boundary

이번 v1 문서 작업에서는 다음을 하지 않는다.

- import pipeline 연결
- UnifiedWorkout 저장소 변경
- 자동 삭제 또는 자동 병합
- HealthKit/Garmin/Samsung 실제 연동
- mapper 변경
- RecoveryCalculator 변경
- Workout Growth Builder 변경
- 사용자용 중복 확인 UI 구현

## Engine v1 Implementation Status

`UnifiedWorkoutDeduplicationEngine`은 현재 순수 Swift 로직으로 구현되어 있다. 입력은 `[UnifiedWorkout]`이고 출력은 `[UnifiedWorkoutDuplicateCandidate]`이다. 엔진은 중복 가능성을 판단할 뿐, 원본 운동을 삭제하거나 병합하지 않는다.

v1 엔진 규칙:

- 같은 `externalId`와 같은 `source`이면 high confidence candidate로 본다.
- fuzzy match는 같은 workout type, 시작 시간 5분 이내, duration 차이 5% 이내를 기본 조건으로 사용한다.
- distance가 둘 다 있으면 차이가 10% 이내일 때만 후보로 인정한다.
- 서로 다른 source에서 유사한 운동이면 cross-source duplicate candidate reason을 추가한다.
- average heart rate가 유사하면 보조 reason으로만 사용한다.
- confidence가 0.75 이상일 때만 candidate를 만든다.

Source priority v1:

- `manual`
- `soomLocal`
- `garmin`
- `appleHealthKit`
- `samsungHealth`
- `healthConnect`
- `unknown`

이 우선순위는 대표 후보를 고르기 위한 힌트이며, 삭제/병합 결정이 아니다. 사용자 수정 또는 수동 기록은 imported data보다 조심스럽게 우선한다.

## Duplicate Review MVP

`UnifiedWorkoutDuplicateReviewView`는 `UnifiedWorkoutStore`에 저장된 최근 30일 workout을 불러와 `UnifiedWorkoutDeduplicationEngine`으로 중복 후보를 확인하는 검토 전용 화면이다.

표시 항목:

- primary workout 요약
- duplicate workout 요약
- confidence
- reasons
- preferredSource
- resolutionPolicy

이 화면은 자동 삭제, 자동 병합, 자동 분석 제외를 수행하지 않는다. 사용자는 후보를 “확인”만 할 수 있으며, 실제 대표 기록 선택/제외/병합 UX는 별도 단계에서 설계한다.

빈 상태는 “중복으로 보이는 운동 기록이 없어요.”로 표시한다. 이 상태는 데이터가 안전하다는 확정 판단이 아니라, 현재 저장된 최근 30일 기록 안에서 v1 엔진 기준 후보가 없다는 의미다.

## Manual Analysis Exclusion MVP

`UnifiedWorkoutLibraryView`에서는 사용자가 특정 workout을 수동으로 “분석 제외” 또는 “분석 포함” 상태로 바꿀 수 있다.

이 기능은 중복 후보를 삭제하거나 병합하지 않고, 향후 Recovery/Growth 계산 입력에서 제외할 수 있는 안전한 flag를 제공하기 위한 단계다.

정책:

- `isExcludedFromAnalysis`는 삭제가 아니라 계산 제외 상태다.
- 원본 workout record는 그대로 보존한다.
- 사용자는 제외된 workout을 다시 분석 포함 상태로 되돌릴 수 있다.
- `UnifiedWorkoutDuplicateReviewView`는 여전히 자동 제외를 수행하지 않는다.
- v1에서는 `RecoveryActivity` / `WorkoutGrowthInput` 생성 흐름에 아직 연결하지 않는다.
- 향후 dedup review에서 중복 후보를 확인한 뒤 사용자가 Library 또는 별도 resolution UI에서 제외 여부를 결정할 수 있다.

`UnifiedWorkoutAnalysisInputSelector`는 이 수동 제외 상태를 derived input 생성 직전에 반영하기 위한 순수 계층이다. 사용자가 중복 후보 중 하나를 분석 제외로 표시하면, selector는 해당 workout을 `RecoveryActivity`와 `WorkoutGrowthInput` 후보에서 제거할 수 있다. 현재는 selector만 준비되어 있으며, DeduplicationEngine이 자동으로 제외 상태를 바꾸지는 않는다.

## Import Pipeline Placement

`UnifiedWorkoutDeduplicationEngine`은 다음 위치에 연결될 예정이다.

```text
Source Fetch
-> Source-specific Mapping
-> UnifiedWorkout Creation
-> Data Quality Evaluation
-> Deduplication Candidate Detection
-> User/Edit Priority Resolution
-> Derived Inputs
```

v1 구현된 엔진은 이 중 `Deduplication Candidate Detection`만 담당한다. import pipeline 연결, primary collection 저장, Recovery/Growth derived input 생성은 아직 하지 않는다.

## Store Responsibility Boundary

`UnifiedWorkoutRecord`와 `SwiftDataUnifiedWorkoutStore`는 로컬 저장 계층이며 deduplication 판단 계층이 아니다.

Store 책임:

- `UnifiedWorkout` 저장/조회
- `externalId + source` 기준 upsert
- `externalId`가 없을 때 `id` 기준 upsert
- `isExcludedFromAnalysis` flag 저장
- 개별 workout 삭제

DeduplicationEngine 책임:

- 시간/거리/운동 타입/심박 유사도 기반 중복 후보 판단
- source priority와 confidence 계산
- representative workout 후보 제안

이 분리를 유지해야 import pipeline에서 저장, 중복 후보 감지, 사용자 검토, 계산 입력 생성을 각각 독립적으로 테스트할 수 있다.
