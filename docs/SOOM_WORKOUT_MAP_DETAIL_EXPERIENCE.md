# SOOM Workout Map Detail Experience

## Product Purpose

Workout Map Detail Experience는 운동 요약 카드, 운동 상세 페이지, 피드 공유 카드가 같은 운동 기록을 서로 다른 깊이로 보여주게 하는 설계다. 목표는 사용자가 오늘 운동이 어제보다, 또는 최근 같은 종목 흐름보다 어떻게 달라졌는지 빠르게 이해하는 것이다.

제품 흐름은 다음 순서를 따른다.

1. Summary Card: 기록 리스트와 피드에서 운동의 핵심 결과를 짧게 보여준다.
2. Detail Page: 지도, 경로, 종목별 지표, 성장 해석을 깊게 보여준다.
3. Feed Reuse: 공유 가능한 요약 카드가 서버 Feed나 로컬 Feed에서 재사용될 수 있게 한다.

이 경험은 RecoveryCalculator나 Recovery score 계산을 변경하지 않는다. Workout/Growth 축에서 운동 기록을 더 잘 이해하게 하는 interpretation layer다.

## Summary Card UX

Summary Card는 피드와 기록 리스트에서 공통으로 재사용 가능한 운동 카드다.

- 경로 데이터가 있으면 static map route preview를 카드 상단 또는 배경 일부로 보여준다.
- 경로 데이터가 없으면 sport-specific visual fallback을 사용한다.
- 러닝은 페이스/거리, 라이딩은 속도/고도, 수영은 100m 페이스, 걷기/하이킹은 거리/고도 흐름을 우선 보여준다.
- 카드를 탭하면 Workout Detail Page로 진입한다.
- 피드에서 사용할 때는 위치, 심박, 파워, 회복 점수 같은 민감 정보를 기본 노출하지 않는다.

Static route preview는 v1에서 두 가지 후보를 둔다.

- Mapbox Maps SDK `Snapshotter`: 앱 내부에서 route polyline을 얹은 snapshot을 생성한다.
- Mapbox Static Images API: 서버 또는 클라이언트에서 URL 기반 static image를 가져온다.

SOOM v1에서는 SDK snapshot 방식을 우선 검토한다. 이미지 export/share card와 같은 로컬 렌더링 흐름으로 관리하기 쉽고, 서버 없이도 동작 방향을 검증할 수 있기 때문이다.

## Detail Page UX

Workout Detail Page는 Mapbox interactive map과 sport-specific metrics를 결합한다.

상단 영역:

- Mapbox interactive map
- route polyline
- start/end marker
- 주요 구간 highlight 후보
- floating overlay metrics: 거리, 시간, 핵심 pace/speed, 상승고도

하단 영역:

- Workout Session Summary
- Workout Growth Metrics
- Growth Summary
- Weakness Insight
- Recovery Impact
- zone cards
- route/elevation detail 후보

지도 위 overlay는 너무 많은 정보를 담지 않는다. 첫 화면에서는 “어디를, 얼마나, 어떤 리듬으로 움직였는지”만 보여주고, 자세한 zone/segment 분석은 아래 섹션으로 둔다.

## Sport-specific Metrics

### Running

- distance
- duration
- avg pace min/km
- splits
- heart rate zone optional
- cadence optional

러닝 상세는 pace와 split rhythm을 중심으로 한다. cadence는 데이터가 있을 때만 보조 지표로 표시하고, cadence zone 기준은 future work로 둔다.

### Cycling

- distance
- duration
- avg speed km/h
- elevation gain
- heart rate zone
- cadence zone
- power zone
- climb/segment analysis future

라이딩 상세는 속도, 고도, 심박존, 케이던스존, 파워존을 장기 핵심 지표로 둔다. 파워존은 FTP가 필요하므로 FTP가 없으면 unavailable 상태로 숨기거나 안내한다.

### Swimming

- distance
- duration
- 100m pace
- laps/strokes future
- heart rate optional

수영 상세는 100m pace와 세션 거리/시간을 우선한다. 랩, 스트로크, SWOLF류 지표는 데이터 source 안정화 이후로 둔다.

### Walking / Hiking

- distance
- duration
- pace
- elevation gain
- route profile

걷기/하이킹은 속도 경쟁보다 경로, 고도, 지속 시간을 중심으로 보여준다.

## Zone Analysis

### Heart Rate Zone

도메인 후보:

- zone1
- zone2
- zone3
- zone4
- zone5
- duration per zone
- percentage per zone

심박존은 운동 강도 해석을 위한 보조 데이터다. 의료/진단 표현을 쓰지 않고 “어느 강도에 오래 머물렀는지”를 설명한다.

### Cadence Zone

도메인 후보:

- low
- optimal
- high
- duration per zone
- percentage per zone

v1 기준 cadence zone은 cycling 중심으로 설계한다. running cadence는 source별 기준과 사용자 체형/목표에 따라 해석이 달라질 수 있으므로 future work로 둔다.

### Power Zone

도메인 후보:

- zone1~zone7
- duration per zone
- percentage per zone
- FTP source
- FTP confidence

Power zone은 FTP가 있어야 의미 있게 표시한다. FTP가 없으면 unavailable 상태로 둔다. FTP 추정이나 자동 보정은 v1 범위에 포함하지 않는다.

## Mapbox Strategy

Mapbox는 두 레벨로 사용한다.

- Interactive detail map: Mapbox Maps SDK for iOS
- Summary/feed card: Mapbox Maps SDK `Snapshotter` 또는 Mapbox Static Images API

Mapbox 공식 iOS 설치 흐름 기준으로 public access token은 `Info.plist`의 `MBXAccessToken` key에 둔다. Secret token은 SDK 설치나 CI 인증 등에 필요할 수 있지만 앱 번들, repo, 문서 예시에 직접 커밋하지 않는다.

Token 정책:

- `MBXAccessToken`: public token, Info.plist runtime config 후보
- secret token: 커밋 금지
- local xcconfig 또는 CI secret 후보
- token 없는 상태에서는 map UI를 fallback visual로 대체

현재 구현에서는 Mapbox SDK가 Swift Package Manager로 추가되었고, `Info.plist`의 `MBXAccessToken`은 `$(MBX_ACCESS_TOKEN)` placeholder를 사용한다. 실제 token 값과 secret token은 repo에 커밋하지 않는다.

## HealthKit Data Requirements

HealthKit 기반으로 map/detail을 구현하려면 다음 데이터가 필요하다.

- `HKWorkout`
- `HKWorkoutRoute`
- Heart Rate samples
- Cycling Cadence samples
- Cycling Power samples
- route altitude 기반 elevation 후보

`HKWorkoutRoute`는 summary card의 route preview와 detail page의 polyline source가 된다. Heart rate, cadence, power는 zone analysis 입력으로 사용한다.

## Data Fallback

데이터가 부족해도 화면은 깨지지 않아야 한다.

- route missing: no map fallback 또는 sport-specific visual fallback
- cadence missing: cadence zone 숨김
- power missing: power zone 숨김 또는 FTP unavailable 안내
- heart rate missing: HR zone 숨김
- elevation missing: elevation 숨김 또는 unavailable 표시
- token missing: Mapbox 영역 대신 neutral route placeholder 표시

Fallback copy는 “데이터가 없어서 분석 불가”보다 “기록이 쌓이면 더 자세히 보여드릴게요” 톤을 우선한다.

## Future Implementation Plan

Phase 1: 설계 문서

Phase 2: route/zone domain models - implemented in v1

Phase 3: HealthKit route fetcher - implemented in v1

Phase 4: Mapbox token/config - implemented with `MBXAccessToken` placeholder, no real token committed

Phase 5: summary static map card - implemented as Static Route Preview Card v1 foundation and AsyncImage loading

Phase 6: detail interactive map page - implemented as Workout Detail Map Overlay Page v1

Phase 7: sport-specific zone cards - implemented with fallback, HealthKit stream, source indicators, and personalized baselines

Phase 8: feed/share reuse - implemented for static route preview with privacy masking; server Feed remains deferred

## Boundaries

- Mapbox SDK는 SPM으로 추가되었지만 실제 Mapbox token 값은 커밋하지 않는다.
- `MBXAccessToken`은 `$(MBX_ACCESS_TOKEN)` placeholder로 유지한다.
- RecoveryCalculator와 Growth 계산 로직을 변경하지 않는다.
- Feed 서버, SNS API, route sharing upload는 구현하지 않는다.
- 위치 데이터는 민감 정보로 취급하며 공유 카드에서는 기본 비공개로 둔다.

## Route / Zone Domain Model v1 Status

Route와 zone 분석을 위한 Swift domain model 1차 구현을 추가했다.

구현된 모델:

- `WorkoutRoute`: workout별 route coordinates, distance, elevation gain, bounds를 담는 domain model
- `WorkoutRouteCoordinate`: latitude, longitude, optional altitude, optional timestamp를 담는 coordinate point
- `WorkoutRouteBounds`: route의 min/max latitude/longitude bounds
- `WorkoutZone`: heart rate, cadence, power zone의 duration과 percentage를 담는 단일 zone row
- `WorkoutZoneSummary`: zone list, dominant zone, coaching insight를 담는 summary model
- `WorkoutZoneBuilder`: raw duration input을 percentage와 dominant zone 중심으로 정리하는 순수 builder

현재 v1 경계:

- Mapbox SDK는 SPM으로 추가되었고 Workout Detail 상단 route hero에서 사용한다.
- Detail map은 `WorkoutRoute` polyline과 floating metrics를 표시하며, token/route가 없으면 fallback visual을 사용한다.
- HealthKit route query는 `HealthKitWorkoutRouteFetcher`로 domain mapping까지 구현되었다.
- Heart rate/cadence/power stream query는 HealthKit metric stream fetcher와 detail-time zone provider로 연결되었다.
- Zone insight는 진단이나 훈련 강요가 아니라 리듬/흐름 중심의 coaching copy로 유지한다.

## HealthKit WorkoutRoute Fetcher v1 Status

`HKWorkoutRoute`를 `WorkoutRoute` domain model로 변환하는 read-only fetch 계층을 추가했다.

구현된 구성:

- `HealthKitWorkoutRouteFetcher`: `HKSampleQuery`로 workout에 연결된 `HKWorkoutRoute`를 찾고, `HKWorkoutRouteQuery`로 `CLLocation` stream을 읽는다.
- `HealthKitWorkoutRouteMapper`: `HKWorkout`과 `CLLocation` 배열을 `WorkoutRoute`로 변환한다.
- `WorkoutRouteStore`: workout id 기준 route 저장/조회가 가능한 가벼운 in-memory cache 프로토콜과 actor 구현이다.

Route mapping 정책:

- `CLLocation.coordinate`를 `WorkoutRouteCoordinate.latitude/longitude`로 보존한다.
- altitude와 timestamp가 있으면 optional field로 보존한다.
- workout distance가 있으면 우선 사용하고, 없으면 location 간 거리 합으로 fallback한다.
- elevation gain은 상승 구간만 더하고, 음수 gain은 route model에서 0 이상으로 보정한다.
- bounds는 route coordinates에서 자동 계산한다.

현재 경계:

- route가 없으면 `nil`로 안전하게 처리한다.
- HealthKit route 권한이 없거나 fetch가 실패하면 caller가 앱 전체 실패로 전파하지 않고 fallback할 수 있어야 한다.
- Detail map은 Mapbox polyline rendering까지 연결되었고, route persistence는 아직 lightweight/in-memory 후보에 머문다.

## Static Route Preview Card v1 Status

WorkoutRoute가 있는 공유/요약 카드에서 Mapbox Static Images API 기반 preview를 준비하는 모델과 URL builder를 추가했다.

구현된 구성:

- `StaticRoutePreview`: static image URL, route bounds, route 존재 여부, sport fallback style을 담는 card-facing model
- `MapboxStaticRouteURLBuilder`: `WorkoutRoute` coordinates를 GeoJSON overlay로 변환해 Mapbox Static Images API URL을 생성한다.
- `StaticRoutePreviewBuilder`: route가 있으면 URL 후보를 만들고, route/token이 없으면 sport-specific fallback을 반환한다.
- `ShareableWorkoutCardModel.staticRoutePreview`: 공유 카드가 route preview를 선택적으로 포함할 수 있는 확장 지점
- `ShareableWorkoutCardView`: route preview가 있는 경우 상단 supporting layer로 표시한다.

Token / loading 정책:

- access token은 `MBXAccessToken` 또는 주입된 token을 사용한다.
- token은 하드코딩하지 않는다.
- Actual Static Map Image Loading v1에서는 `ShareableWorkoutCardView`가 `StaticRoutePreview.imageURL`을 `AsyncImage`로 로드할 수 있다.
- loading/failure/token 없음 상태는 sport-specific fallback으로 조용히 전환한다.

현재 경계:

- Static share/feed card는 Mapbox SDK interactive view를 사용하지 않고 URL/AsyncImage 기반으로 동작한다.
- Detail interactive map과 share/feed static preview는 분리한다.
- route polyline animation 없음
- route privacy masking v1 적용: static route preview 생성 전 start/end 주변 좌표를 기본 200m 기준으로 제거할 수 있다.
- RecoveryCalculator와 Growth 계산 로직 변경 없음

## Actual Static Map Image Loading v1 Status

Share/feed card의 route preview는 이제 `StaticRoutePreview.imageURL`이 있을 때 `AsyncImage`로 실제 Mapbox Static Images 결과를 로드할 수 있다. 지도 이미지는 카드의 supporting layer로만 사용하며, 거리/시간/성장 메시지보다 강하게 보이지 않도록 낮은 대비 overlay를 둔다.

UX 정책:

- loading 상태는 subtle placeholder로 유지한다.
- image load 실패, token 없음, route 없음, masking 후 route 부족 상태는 sport-specific fallback으로 전환한다.
- route image는 `StaticRoutePreviewBuilder`가 만든 masked route URL만 사용한다. 원본 route를 view에서 직접 노출하지 않는다.
- share/feed static preview는 detail interactive Mapbox view와 분리되어 있으며, image-level animation과 server upload는 아직 구현하지 않는다.

## Route Privacy Masking v1 Status

Route preview가 feed/share/export 맥락에 노출되기 전에 시작/종료 지점 주변을 제거하는 privacy masking 구조를 추가했다.

구현된 구성:

- `RoutePrivacyMaskingPolicy`: `none`, `startAndEnd`, `startOnly`, `endOnly` mode와 masking distance를 정의한다.
- `RoutePrivacyMasker`: 원본 `WorkoutRoute`를 변경하지 않고 preview/share용 파생 `WorkoutRoute`를 만든다.
- 기본 share/static preview 정책은 `startAndEnd`, `200m` masking이다.
- 내부 검증이나 비공개 preview에서는 `.none` policy를 명시적으로 사용할 수 있다.
- masking 후 route가 너무 짧아져 2개 미만 coordinate만 남으면 static preview는 fallback으로 처리한다.

현재 경계:

- user privacy settings UI는 아직 없다.
- blur/mosaic 같은 image-level masking은 아직 없다.
- Mapbox SDK는 SPM으로 추가됐고 Workout Detail 상단의 개인용 route overlay hero에 사용한다.
- share/feed static card는 detail interactive map과 분리되어 있으며, privacy masking된 route preview만 사용한다.

## Workout Detail Map Overlay Page v1 Status

Workout Detail 상단에 Mapbox 기반 route map overlay를 붙이는 v1 구조를 추가했다. `WorkoutRoute`가 있으면 Mapbox Maps SDK의 map view 위에 route polyline을 표시하고, 같은 hero 영역 위에 거리/시간/종목별 핵심 지표를 floating metric overlay로 보여준다.

- Mapbox Maps SDK는 Swift Package Manager dependency로 추가한다.
- public token은 `Info.plist`의 `MBXAccessToken`을 사용하며, repo에는 실제 token을 커밋하지 않는다. 현재 기본값은 `$(MBX_ACCESS_TOKEN)` placeholder다.
- token이 없거나 route가 없거나 swimming처럼 route 표시가 자연스럽지 않은 경우 sport-specific fallback visual을 사용한다.
- Detail page의 map은 supporting hero layer이며, Growth/Zone/Recovery interpretation section은 기존 순서대로 아래에 유지한다.
- route replay animation, segment replay, Mapbox interactive detail 고도화는 아직 구현하지 않는다.


## Zone Cards v1 Status

Zone Cards v1 adds `WorkoutZoneCard` and `WorkoutZoneSection` to the Workout Detail interpretation flow. The cards render `WorkoutZoneSummary` as simple distribution bars with dominant-zone and coaching copy, and sit below Growth Metrics and before Weakness/Recovery Impact.

Sport-specific handling is intentionally lightweight:

- Running: heart-rate zone first, cadence zone when cadence is available.
- Cycling/Brick: heart-rate, cadence, and power zone. Missing power data is shown as unavailable rather than as a failure.
- Swimming: heart-rate zone only for v1, with stroke/lap zones left for future work.
- Walking/Hiking future: heart-rate-centered zone cards can reuse the same summary model.

This remains a coaching layer, not a training dashboard. FTP, NP, TSS, IF, advanced power modeling, and chart-heavy analysis are deferred.

## HealthKit Metric Stream Zone Expansion v1

Zone Cards can now be backed by a HealthKit stream fetch/mapping layer. v1 adds the domain path for workout-linked heart rate, cycling cadence, and cycling power samples without changing the Workout Detail visual hierarchy.

Flow:

1. `HealthKitWorkoutMetricStreamFetcher` fetches samples attached to a selected `HKWorkout`.
2. `HealthKitWorkoutMetricMapper` normalizes sample values and units.
3. `HealthKitMetricZoneBuilder` groups sample durations into `WorkoutZoneSummary`.
4. `WorkoutZoneCard` and `WorkoutZoneSection` can display the resulting summaries when the detail flow connects real stream data.

Zone policy:

- Heart rate uses user maxHR-based personalized Zone 1-5 thresholds when Settings has maxHR; otherwise it falls back to a generic max HR.
- Cycling cadence uses low / optimal / high rhythm buckets.
- Cycling power uses Settings cycling FTP for Zone 1-7 when available; when FTP is missing, power remains a gentle unavailable summary rather than a training-dashboard calculation.

Deferred:

- FTP auto-estimation
- advanced cycling metrics such as NP, TSS, IF
- complex charting
- automatic HealthKit stream sync
- Garmin/Samsung stream import


## Real Zone Stream Injection v1

Workout Detail Zone Cards now have a real-data injection path for HealthKit metric streams. When an `HKWorkout` and `WorkoutZoneDataProvider` are available, SOOM fetches heart-rate, cycling cadence, and cycling power samples, maps them into `HealthKitWorkoutMetricSample`, and builds `WorkoutZoneSummary` values for the detail page.

The UI still keeps the existing fallback summaries when stream data is empty or unavailable. Power remains FTP-gated in v1: without FTP, cycling power appears as a gentle unavailable state rather than a training-dashboard calculation.

## Imported HealthKit Workout Detail Context v1

Real Zone Stream Injection is now connected to imported Apple HealthKit workout detail entry. When a stored `UnifiedWorkout` comes from Apple HealthKit and keeps the original workout UUID in `externalId`, SOOM can look up the `HKWorkout` at detail time and pass it with `WorkoutZoneDataProvider` into `WorkoutDetailContent`.

Behavior:

- Apple HealthKit + valid `externalId`: try `HKWorkout` lookup and prefer real HR/cadence/power stream summaries.
- Non-HealthKit source: do not query HealthKit and keep fallback summaries.
- Missing id, permission issue, or lookup failure: keep fallback summaries with no crash.
- This remains detail-time only and does not change RecoveryCalculator, Growth calculations, automatic sync, or Garmin/Samsung support.

## Zone Source Indicator v1

Zone Cards now include a small source indicator so users can understand whether the card is based on real stream data, a safe fallback estimate, or an unavailable sensor stream.

Source states:

- `HealthKit 데이터`: built from workout-linked HealthKit sensor samples.
- `기본 추정`: built from existing workout summary fields when stream data is not available.
- `데이터 없음`: shown when a sport-specific sensor stream, such as cycling power, is not present or cannot be used yet.

The indicator is a trust cue, not a warning. Missing cadence, heart-rate, or power streams should feel like normal device/sensor coverage limits, not an app error. RecoveryCalculator, Growth calculations, FTP policy, and stream fetch behavior remain unchanged.

## Training Baseline Settings v1

Settings/My Page now has a lightweight place for user training baseline values such as max heart rate and cycling FTP. These values are stored locally and are used by Workout Detail Zone Cards to personalize heart-rate and cycling power zone calculation.

Policy:

- max heart rate is validated as 80...230 bpm.
- cycling FTP is validated as 50...500 W.
- max heart rate personalizes heart-rate zones, and cycling FTP personalizes power zones when available.
- FTP auto-estimation, NP/TSS/IF, and advanced cycling metrics remain deferred.
- RecoveryCalculator and Growth calculations are not changed by these settings.

## Personalized Zone Baseline v1

Settings/My Page에 저장한 max heart rate와 cycling FTP가 Workout Detail Zone Cards의 zone calculation에 연결되었다.

- Heart Rate Zone은 max heart rate가 있으면 사용자 기준 비율로 계산한다: Zone 1 <60%, Zone 2 60~70%, Zone 3 70~80%, Zone 4 80~90%, Zone 5 90%+.
- Power Zone은 cycling FTP가 있으면 FTP 비율 기반 Zone 1~7로 계산한다: Z1 <55%, Z2 56~75%, Z3 76~90%, Z4 91~105%, Z5 106~120%, Z6 121~150%, Z7 sprint.
- FTP가 없으면 기존처럼 power zone은 unavailable로 남긴다.
- Zone Cards에는 `최대심박 기준` 또는 `FTP 기준` 같은 작은 trust cue를 표시한다.
- NP, TSS, IF, FTP auto-estimation, RecoveryCalculator 변경, Growth calculation 변경은 포함하지 않는다.


## Route Comparison Insight v1

Workout Detail now has a lightweight comparison layer for the current workout and a previous similar route or similar-distance workout. v1 intentionally avoids complex map matching, segment replay, and ML prediction.

Implemented pieces:

- `RouteComparisonCandidate` stores a candidate workout id, similarity score, reason, and matched distance metadata.
- `RouteSimilarityBuilder` finds candidate routes using distance tolerance, route bounds overlap, and start/end proximity.
- `WorkoutComparisonInsightBuilder` compares the current `WorkoutGrowthInput` with a baseline workout and creates sport-specific rows such as running pace, cycling average speed/elevation, or swimming 100m pace.
- `WorkoutComparisonInsightCard` is placed after Growth Metrics and before Zone Analysis in Workout Detail.

Boundary:

- This is a candidate/insight layer, not Strava-style segment matching.
- Route matching is approximate and explanation-first.
- RecoveryCalculator, official Recovery score, existing Growth calculations, Feed/SNS, server/Auth, and Garmin/Samsung connectors are not changed.

## Similar Workout Candidate Provider v1

Route Comparison Insight can now receive comparison baselines from stored UnifiedWorkout history. In imported workout detail, `SimilarWorkoutCandidateProvider` fetches recent same-sport workouts from `UnifiedWorkoutStore`, removes analysis-excluded records, and returns the best baseline for `WorkoutComparisonInsightBuilder`.

Route handling remains intentionally lightweight:

- If current and candidate `WorkoutRoute` values are available, route similarity can rank candidates.
- If routes are unavailable, similar-distance fallback selects a comparable baseline.
- Complex map matching, segment replay, server sync, and ML prediction remain deferred.
- RecoveryCalculator and Growth calculation logic remain unchanged.
