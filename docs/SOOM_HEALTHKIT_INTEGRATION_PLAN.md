# SOOM HealthKit Integration Plan

## Purpose

SOOM은 장기적으로 Apple 건강 앱과 Apple Watch 운동 기록을 읽어 Recovery, 운동 흐름, AI Coach 문장을 더 정확하게 만들 수 있어야 한다. Phase 1은 실제 Recovery 점수 계산에 HealthKit 데이터를 연결하지 않고, read-only 권한 흐름과 workout fetch 기반만 준비한다.

HealthKit은 SOOM의 유일한 건강 데이터 원천이 아니라 Unified Health Data Source 중 하나다. 장기적으로 Apple HealthKit, Garmin, Samsung Health, SOOM 자체 기록은 [SOOM_UNIFIED_HEALTH_DATA_SOURCE.md](SOOM_UNIFIED_HEALTH_DATA_SOURCE.md)의 공통 모델로 정제된 뒤 Recovery와 Workout Growth에 전달한다.

## Phase 1 Scope

Phase 1에서 준비하는 것:

- `HealthKitManager`: HealthKit 사용 가능 여부 확인과 read-only 권한 요청
- `HealthKitWorkout`: SOOM 내부에서 사용할 HealthKit workout snapshot 모델
- `HealthKitWorkoutFetcher`: 최근 workout을 읽어오는 fetch 구조
- `HealthKitStatusCard`: Settings/Preview 후보 상태 카드
- `Info.plist`의 HealthKit read usage description

Phase 1에서 하지 않는 것:

- `RecoveryCalculator` 입력으로 HealthKit 데이터 연결
- Recovery score/status/recommendation 변경
- HealthKit write 권한 요청
- HRV, 수면, resting heart rate 통합
- Cloud sync, 서버 저장, ML/LLM 요약

## Permission Strategy

SOOM v1의 HealthKit 권한 전략은 최소 read-only 원칙을 따른다.

요청 후보:

- Workout
- Workout Route
- Heart Rate
- Active Energy Burned
- Walking + Running Distance
- Cycling Distance

정책:

- write 권한은 요청하지 않는다.
- 사용자가 명확히 이해할 수 있는 시점에만 권한을 요청한다.
- Recovery 화면 진입만으로 권한을 강제하지 않는다.
- 권한 거부가 앱 전체 실패로 이어지지 않게 한다.

## Data Model Strategy

`HealthKitWorkout`은 `RecoveryActivity`와 분리된 앱 내부 모델이다.

포함 필드:

- `id`
- `workoutType`
- `startDate`
- `endDate`
- `duration`
- `distance`
- `averageHeartRate`
- `calories`

Phase 1에서는 `HKWorkout`을 `HealthKitWorkout`으로 변환하는 수준까지만 둔다.

Phase 2에서는 `HealthKitRecoveryActivityMapper`와 `HealthKitActivityStore`를 추가해 `HealthKitWorkout`을 `RecoveryActivity`로 변환할 수 있게 한다. 단, 이 store는 아직 production 기본 store로 연결하지 않으며, Recovery score 계산에도 사용하지 않는다.

Unified Health 단계에서는 기존 HealthKit 구조를 유지한 채 `HealthKitWorkoutToUnifiedWorkoutMapper`를 추가했다. 이 mapper는 `HealthKitWorkout`을 source-independent `UnifiedWorkout`으로 변환하며, 아직 `RecoveryActivity` 또는 Workout Growth 입력으로 연결하지 않는다.

## Phase 2 Mapping Policy

`HealthKitRecoveryActivityMapper`는 HealthKit 원천 모델과 Recovery 계산 입력 모델을 분리하기 위한 얇은 변환 계층이다.

매핑 정책:

- `running` → `RecoveryWorkoutType.run`
- `cycling` → `RecoveryWorkoutType.ride`
- `swimming` → `RecoveryWorkoutType.swim`
- `walking` → `RecoveryWorkoutType.run`
- `other` → `RecoveryWorkoutType.run`

`RecoveryWorkoutType`에는 아직 walking/other가 없으므로, 걷기와 기타 운동은 회복성 러닝 계열 fallback으로 처리한다. 향후 걷기, 근력, 요가, 기타 운동 타입을 별도 Recovery taxonomy로 확장할 수 있다.

MVP 추정 정책:

- `duration`은 분 단위로 변환한다.
- `distance`는 meter에서 kilometer로 변환한다.
- `averageHeartRate`가 없으면 0으로 안전하게 보정한다.
- `relativeEffort`와 `trainingLoad`는 duration, averageHeartRate, calories를 사용한 단순 추정값이다.
- 실제 훈련 부하 계산은 TRIMP, HR zone, power, sport-specific load가 준비된 뒤 교체한다.

## Recovery Integration Plan

다음 단계 후보:

1. `HealthKitRecoveryActivityMapper`로 `HealthKitWorkout`을 `RecoveryActivity`로 변환한다. 완료.
2. `HealthKitActivityStore`가 `RecoveryActivityStore`를 채택한다. 완료.
3. `ActivityRecoveryDataProvider` 또는 `CombinedRecoveryDataProvider`에 store 교체 가능성 추가
4. 기존 mock/local store와 HealthKit store를 feature flag 또는 DI로 분리
5. 권한 UX와 실제 production 연결은 별도 단계에서 진행

중요 정책:

- HealthKit 연결 후에도 `RecoveryCalculator` 공식 변경은 별도 단계에서만 진행한다.
- HealthKit 데이터가 비어 있거나 권한이 없어도 기존 mock/local Recovery 흐름은 유지한다.
- HealthKit fetch 실패는 Recovery 화면 전체 실패로 전파하지 않는다.

## Phase 3 Settings UX

Phase 3에서는 사용자가 HealthKit 연결 상태를 확인하고 read-only 권한 요청을 시작할 수 있는 최소 설정 UI를 제공한다.

구성:

- `HealthKitSettingsViewModel`: `HealthKitManager`를 주입받아 사용 가능 여부, 요청 진행 상태, 오류 메시지를 관리한다.
- `HealthKitSettingsView`: 연결 상태 카드, read-only 정책 설명, 권한 요청 버튼을 제공한다.
- `HealthKitSettingsViewContainer`: production 진입에서 `HealthKitManager`를 주입한다.
- Recovery 화면 하단의 관리 액션에서 `HealthKit 연결`로 진입한다.

권한 UX 정책:

- SOOM은 현재 읽기 권한만 요청한다.
- 권한 요청 성공은 실제 모든 read 권한 허용을 보장하지 않으므로 “요청 완료 / 건강 앱에서 확인 필요”에 가까운 상태로 표현한다.
- 권한 거부, 미지원 기기, 요청 실패는 앱 전체 오류로 전파하지 않는다.
- HealthKit 연결 UI는 Recovery 핵심 카드가 아니라 설정/관리 영역에 둔다.
- HealthKit 데이터는 아직 Recovery score/status/recommendation에 반영하지 않는다.

## Phase 4 Workout Preview

Phase 4에서는 권한 요청 이후 HealthKit에서 불러올 수 있는 최근 운동 기록을 사용자가 직접 확인할 수 있는 preview UI를 제공한다.

구성:

- `HealthKitWorkoutPreviewViewModel`: `HealthKitWorkoutFetching`을 주입받아 최근 workout 목록, loading, error state를 관리한다.
- `HealthKitWorkoutPreviewView`: 운동 타입, 날짜, 시간, 거리, 평균 심박, 칼로리를 간단한 목록으로 보여준다.
- `HealthKitWorkoutPreviewViewContainer`: production 진입에서 `HealthKitWorkoutFetcher`를 주입한다.
- `HealthKitSettingsView` 하단에서 “최근 운동 기록 미리보기”로 진입한다.

Preview UX 정책:

- 이 화면은 연결 확인용 보조 화면이다.
- HealthKit workout이 보여도 아직 Recovery score/status/recommendation에 반영하지 않는다.
- 권한이 없거나 fetch가 실패하면 Recovery 화면 전체 오류로 전파하지 않고 preview 화면 안에서만 안내한다.
- 빈 상태는 “아직 불러올 운동 기록이 없어요”처럼 부담 없는 문장으로 표시한다.
- 운동 상세 화면이나 복잡한 분석은 만들지 않고, 최근 목록 확인에만 집중한다.

## Phase 5 Recovery Activity Source Flag

Phase 5에서는 HealthKit workout을 Recovery 계산의 기본 입력으로 바꾸지 않고, 내부 개발용 source flag로만 선택 가능하게 준비한다.

구성:

- `RecoveryActivitySource`: `.mock`, `.local`, `.healthKit` source를 표현한다.
- `RecoveryDataProviderFactory`: source에 따라 `ActivityRecoveryDataProvider`와 적절한 `RecoveryActivityStore`를 조합한다.
- `RecoveryViewContainer`: 내부 개발용으로 `activitySource`를 주입받을 수 있지만, 기본값은 기존 mock-backed Recovery 흐름을 유지한다.

Source 정책:

- `.mock`: 기존 `MockRecoveryActivityStore` 기반 흐름. 현재 기본값이다.
- `.local`: `LocalActivityStore` 기반 흐름. 앱 내부 workout snapshot 연결 후보이다.
- `.healthKit`: `HealthKitActivityStore` 기반 흐름. 개발용 검증 후보이며 production 기본값이 아니다.

중요 정책:

- HealthKit source를 선택해도 `RecoveryCalculator` 공식은 변경하지 않는다.
- HealthKit 권한 요청은 factory/provider 생성 시점에 실행하지 않는다.
- HealthKit fetch 실패나 데이터 없음은 `HealthKitActivityStore`의 graceful fallback 정책을 따른다.
- 사용자용 source 선택 UI는 만들지 않는다.

### HealthKit Source Smoke Test 방법

HealthKit source는 아직 앱의 기본 Recovery 입력이 아니다. 기본 앱 실행 흐름은 mock/local 기반 Recovery를 유지한다.

내부 개발자가 HealthKit source를 검증할 때는 다음 순서로 확인한다.

1. `HealthKitRecoverySourceSmokeTests`를 실행해 fake workout fetcher 기반으로 `HealthKitActivityStore -> RecoveryActivity -> RecoverySummary` 흐름이 깨지지 않는지 확인한다.
2. 앱에서 HealthKit 연결 설정 화면을 통해 read-only 권한 요청 흐름을 확인한다.
3. Workout Preview 화면에서 최근 HealthKit workout이 읽히는지 확인한다.
4. 내부 개발 빌드에서만 `RecoveryViewContainer(activitySource: .healthKit)`를 사용해 Recovery source 전환을 수동 검증할 수 있다.

주의:

- smoke test는 실제 `HKHealthStore`에 접근하지 않는다.
- fake `HealthKitWorkoutFetching`을 사용하므로 HealthKit 권한 요청이 발생하지 않는다.
- `.healthKit` source를 production 기본값으로 바꾸는 것은 별도 단계에서 결정한다.
- HealthKit workout이 RecoverySummary로 변환되더라도 score 공식 자체는 기존 `RecoveryCalculator` 규칙을 그대로 사용한다.

## Phase 6 HealthKit Recovery Preview

HealthKit Recovery Preview는 HealthKit source로 계산한 `RecoverySummary`를 production 전 단계에서 확인하기 위한 개발/검증용 화면이다.

표시 범위:

- HealthKit source 기반 recovery score
- status
- recommendation
- coach message
- data quality
- 개발용 미리보기 안내

정책:

- 기본 Recovery source는 변경하지 않는다.
- `RecoveryViewContainer` 기본값은 기존 mock-backed 흐름을 유지한다.
- 사용자용 source picker UI는 만들지 않는다.
- HealthKit Preview 결과는 production Recovery 화면에 자동 반영하지 않는다.
- HealthKit 권한 실패, workout 부족, fetch 실패는 preview 화면 안에서만 안내한다.
- score/status/recommendation은 provider가 반환한 값을 그대로 표시하며, preview 화면에서 재계산하거나 보정하지 않는다.

이 화면은 현재 HealthKit Settings 하단의 보조 진입점으로만 제공한다. 추후 내부 Developer Menu가 생기면 해당 영역으로 이동하는 후보이다.

## Future v2 Inputs

v2 이후 후보:

- HRV
- Resting Heart Rate
- Sleep Duration / Sleep Quality
- Workout route metadata
- Power / cadence / swimming stroke data
- Wearable data confidence

이 입력들은 Phase 1 scope 밖이다.

## Privacy Principles

HealthKit 데이터는 민감한 건강 관련 데이터로 취급한다.

- 로컬 우선 처리
- 최소 권한 요청
- 사용자 동의 없는 서버 전송 금지
- 의료 진단처럼 표현 금지
- 권한 거부 시에도 앱 핵심 경험이 깨지지 않도록 graceful fallback 유지

## Implementation Status

Phase 1 완료 기준:

- read-only HealthKit 권한 후보 정의
- HealthKit manager/fetcher/model 생성
- HealthKit status card preview 준비
- Recovery/Check-in/SwiftData 흐름에는 연결하지 않음
- build/test 성공 확인

Phase 2 완료 기준:

- `HealthKitRecoveryActivityMapper` 생성
- `HealthKitActivityStore` 생성
- `HealthKitWorkoutFetching` protocol 기반 테스트 주입 가능
- HealthKit workout을 RecoveryActivity로 변환하는 단위 테스트 추가
- HealthKitActivityStore fake fetcher 기반 테스트 추가
- RecoveryCalculator 기본 입력과 Recovery 화면에는 아직 연결하지 않음

Phase 3 완료 기준:

- `HealthKitSettingsViewModel` 생성
- `HealthKitSettingsView`와 container 생성
- Recovery 하단 관리 액션에서 HealthKit 연결 화면 진입
- fake manager 기반 ViewModel 테스트 추가
- read-only 권한 요청 UX 문서화
- RecoveryCalculator, ActivityRecoveryDataProvider 기본 store, score/status/recommendation 변경 없음

Phase 4 완료 기준:

- `HealthKitWorkoutPreviewViewModel` 생성
- `HealthKitWorkoutPreviewView`와 container 생성
- HealthKit 설정 화면에서 최근 운동 기록 preview 진입
- fake workout fetcher 기반 ViewModel 테스트 추가
- workout preview가 Recovery score 계산과 분리되어 있음

Phase 5 완료 기준:

- `RecoveryActivitySource` 생성
- `RecoveryDataProviderFactory` 생성
- `RecoveryViewContainer`에 내부 개발용 activity source 주입 지점 추가
- factory source별 provider 생성 테스트 추가
- 기본 Recovery 입력은 기존 mock-backed 흐름 유지

Phase 7 완료 기준:

- `HealthKitWorkoutImportPipeline` 생성
- `HealthKitWorkoutImportResult` 생성
- `HealthKitWorkoutFetching -> HealthKitWorkoutToUnifiedWorkoutMapper -> UnifiedWorkoutStore` import path 추가
- HealthKit workout을 `UnifiedWorkoutStore`에 저장하는 테스트 추가
- 같은 `externalId + source` 재import는 store upsert 정책으로 중복 증가를 막음
- Recovery 기본 source, RecoveryCalculator, Workout Growth 입력은 변경하지 않음

Phase 8 완료 기준:

- `HealthKitWorkoutImportViewModel` 생성
- `HealthKitWorkoutImportView`와 container 생성
- HealthKit 설정 화면에서 수동 import preview 진입 추가
- 사용자가 fetched/saved/skipped/failed count와 message를 확인할 수 있음
- 가져온 `UnifiedWorkout`은 아직 Recovery/Growth에 자동 반영하지 않음
- DeduplicationEngine 자동 적용, Recovery 기본 source 전환, Workout Growth 입력 전환은 하지 않음

Phase 9 완료 기준:

- `RecoveryRealDataPreviewViewModel`, `RecoveryRealDataPreviewView`, `RecoveryRealDataPreviewViewContainer` 생성
- `UnifiedWorkoutRecoveryPreviewProvider`가 `UnifiedWorkoutStore`에 저장된 imported workout을 Recovery preview summary로 변환
- HealthKit 설정/관리 영역에서 “실제 운동 기반 Recovery 미리보기” 진입 제공
- 가져온 HealthKit workout은 preview 계산에 사용할 수 있지만, 기본 Recovery score에는 자동 반영하지 않음
- Real Data Preview는 기본 Recovery 전환 전 검증/비교 단계이며, 사용자는 이 결과를 공식 점수가 아니라 imported workout 기반 미리보기로 이해해야 함
- Recovery Comparison Preview는 공식 Recovery와 imported workout 기반 preview의 차이를 설명하는 UX이며, 기본 provider 전환 전 검증 단계로 유지함
- DeduplicationEngine 자동 적용, HealthKit source 기본 전환, RecoveryCalculator 변경은 하지 않음



## Manual Import Entry UX

HealthKit workout import is a manual action in v1. SOOM does not auto-sync HealthKit workouts in the background. Users reach it through the Recovery management area by selecting `HealthKit 운동 가져오기`, then the HealthKit settings screen shows `HealthKit 운동 가져오기` near the top under the connection status.

Current path:

1. Recovery 관리 영역
2. HealthKit 운동 가져오기
3. HealthKit 운동 가져오기 화면
4. 수동 가져오기 버튼

Implementation boundary:

- The import button runs `HealthKitWorkoutFetcher -> HealthKitWorkoutToUnifiedWorkoutMapper -> SwiftDataUnifiedWorkoutStore -> HealthKitWorkoutImportPipeline`.
- Imported workouts can be used for Growth analysis and Recovery preview flows.
- Imported workouts are not automatically applied to the official Recovery provider.
- DeduplicationEngine is not automatically applied during import.
- Garmin/Samsung sources remain future connector candidates.

## Manual Import Entry UX Update

HealthKit manual import is intentionally discoverable from the Record tab, not only from Recovery management. The primary path is now:

1. Record tab
2. Data Connection
3. Apple Health workout import
4. Manual import button

The import flow remains user-initiated. SOOM does not auto-sync HealthKit workouts in this phase. The runtime path is:

HealthKitWorkoutFetcher -> HealthKitWorkoutToUnifiedWorkoutMapper -> SwiftDataUnifiedWorkoutStore -> HealthKitWorkoutImportPipeline.

Imported workouts can support Growth analysis through UnifiedWorkout-based providers and can be used in Recovery preview screens. They are still not connected to the official Recovery provider, and DeduplicationEngine is not applied automatically.

The app target includes the read-only HealthKit entitlement through `SOOM/SOOM.entitlements`. `NSHealthShareUsageDescription` remains in `SOOM/Info.plist`; no write permissions are requested.

## HealthKit WorkoutRoute Fetch v1

Workout map/detail 확장을 위해 HealthKit route read path를 domain mapping 단계까지 준비했다.

구성:

- `HealthKitManager.readTypes`에 `HKSeriesType.workoutRoute()`를 포함한다.
- `HealthKitWorkoutRouteFetcher`는 특정 `HKWorkout`에 연결된 `HKWorkoutRoute` sample을 찾고 `HKWorkoutRouteQuery`로 `CLLocation` stream을 읽는다.
- `HealthKitWorkoutRouteMapper`는 `HKWorkout + [CLLocation]`을 `WorkoutRoute`로 변환한다.
- `WorkoutRouteStore`는 SwiftData persistence 전 단계의 가벼운 workout id 기반 route cache 후보로 둔다.

Mapping policy:

- route coordinate, altitude, timestamp를 가능한 한 보존한다.
- workout total distance가 있으면 우선 사용하고, 없으면 location 간 거리 합으로 fallback한다.
- elevation gain은 상승분만 더하며 음수 값은 domain model에서 0 이상으로 보정한다.
- route가 없거나 권한이 부족하면 `nil` 또는 fetch failure로 안전하게 처리하고, 앱 전체 실패로 전파하지 않는다.

현재 하지 않는 것:

- Mapbox SDK 설치 또는 지도 UI 연결
- route polyline rendering
- route SwiftData persistence
- background route fetch
- RecoveryCalculator 또는 Growth 계산 로직 변경

## HR / Cadence / Power Stream Fetch v1

HealthKit stream read path now includes a first implementation for workout-attached heart rate, cycling cadence, and cycling power samples.

Implemented structure:

- `HealthKitWorkoutMetricSample` stores a normalized sample type, value, unit, start date, and end date.
- `HealthKitWorkoutMetricStreamFetcher` uses `HKSampleQuery` with `HKQuery.predicateForObjects(from:)` to fetch samples linked to a specific `HKWorkout`.
- `HealthKitWorkoutMetricMapper` maps `HKQuantitySample` values into SOOM metric samples with read-only units: heart rate `count/min`, cycling cadence `rpm`, and power `watt`.
- `HealthKitMetricZoneBuilder` converts metric samples into `WorkoutZoneSummary` for Zone Cards.
- `HealthKitManager.readTypes` includes heart rate and, on iOS 17+, cycling cadence and cycling power. No write permission is requested.

Current boundary:

- This prepares real stream data for Workout Detail Zone Cards, but does not change RecoveryCalculator, Growth analysis, or official Recovery score behavior.
- FTP settings, NP/TSS/IF, automatic HealthKit sync, and Garmin/Samsung streams remain deferred.


## Stream Fetch to Zone Cards v1

HealthKit metric streams can now feed Workout Detail Zone Cards through `WorkoutZoneDataProvider`. The flow is manual/detail-time only: `HKWorkout` -> `HealthKitWorkoutMetricStreamFetcher` -> `HealthKitMetricZoneBuilder` -> `WorkoutZoneSummary` -> `WorkoutZoneSection`.

This is not background sync and does not change RecoveryCalculator or Growth calculations. Missing HR, cadence, or power data falls back to existing summary/unavailable UI so sensor-dependent gaps do not look like app errors.

## Imported Workout Detail Zone Context v1

HealthKit imported workout detail can now reconnect to real HealthKit context at detail time. `UnifiedWorkout.externalId` is treated as the HealthKit workout UUID when `source == .appleHealthKit`. The detail context flow is:

`UnifiedWorkout.externalId -> HealthKitWorkoutLookupProvider -> HKWorkout -> WorkoutZoneDataProvider -> WorkoutZoneSection`.

If permission is missing, the workout cannot be found, or the imported workout is not from Apple HealthKit, SOOM keeps the existing fallback zone summary. This is a manual/detail-time lookup only; it does not enable automatic HealthKit sync and does not change RecoveryCalculator or Growth calculations.

## Settings / My Page Access

HealthKit connection management should be reachable from both the Record data-connection flow and Settings/My Page. Settings provides a stable management home for permission state, manual import, workout library review, and future privacy/training baseline controls.

This does not introduce automatic HealthKit sync. Manual import remains explicit, and imported workouts can support Growth analysis and Recovery preview without replacing the official Recovery provider.
