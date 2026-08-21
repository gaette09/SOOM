# SOOM Record UX Architecture

## 목적과 범위

이 문서는 기존 SOOM iOS Record 기능을 유지하면서 Strava/Garmin 수준의 Recording UX로 확장하기 위한 현재 아키텍처 분석과 개선 계획을 기록한다.

- 이번 단계에서는 코드, navigation, GPS/Map/Tracking 로직을 변경하지 않는다.
- 새 Record feature를 만들지 않는다. 기존 `RecordView`, `RecordWorkoutSession`, `RecordLocationManager`, `RecordMapView`, `RecordWorkoutSaver`를 확장의 기반으로 재사용한다.
- 분석 기준은 `Before Ride → Live → Finish`이다.

## 현재 흐름

```text
RootTabView
  └─ 중앙 Record 탭 선택
      └─ fullScreenCover + NavigationStack
          └─ RecordView
              ├─ Before Ride: 종목 선택 / 추천 route / 위치·날씨 준비
              ├─ Live: RecordWorkoutSession + RecordLocationManager + RecordMapView + HUD
              └─ Finish: RecordWorkoutSummary → UnifiedWorkout + WorkoutRoute 저장
                                      └─ 선택 시 FeedShareDraft 생성
```

## 1. Record 진입 및 fullScreenCover 구조

`RootTabView`의 중앙 Record action은 탭 선택을 바꾸지 않고 `isRecordLaunchPresented`를 설정한다. `RecordView`는 `fullScreenCover` 내부의 독립 `NavigationStack`에서 열린다.

| 종료 결과 | 현재 root 처리 | 유지 원칙 |
| --- | --- | --- |
| 닫기/취소 | Feed 탭으로 복귀 | 현재 behavior 유지 |
| 저장 완료 | Activity 탭으로 복귀 | Activity library에서 저장 결과를 보게 함 |
| Feed draft 생성 완료 | Feed 탭으로 복귀 | draft가 Feed source에 병합됨 |

이 방식은 recording 중 tab bar와 기존 탭 stack을 분리하므로 유지한다. 개선 단계에서도 새 router/path를 만들지 않고 현재 closure(`onDismiss`, `onSaveComplete`, `onShareDraftComplete`)의 결과 계약을 유지한다.

## 2. Before Ride 분석

### 현재 구성

- `RecordView`는 `selectedSport`, `selectedRoute`, 날씨 snapshot, 위치 상태를 보유한다.
- 시작 제어는 READY button의 drag/radial interaction이다. Cycling, Running, Walking 중 하나를 선택하면 `RecordWorkoutSessionStarter.start`가 session을 만든다.
- Cycling은 현재 별도 bike profile/device 선택이 아니라 `RecordSportMode.cycling` 하나로 선택된다.
- `RecordLaunchPlan.mockToday`가 기본 종목과 추천 route를 제공한다.
- 위치 권한이 없어도 local-first 시간 기록을 시작할 수 있다. 시작 시 위치가 있으면 `startedWithLocation`과 route capture 준비 상태가 설정된다.
- Mapbox token이 없을 경우 `RecordMapFallbackSurface`로 대체된다.

### 현재 UX와 목표의 차이

| 목표 | 현재 상태 | 개선 방향 |
| --- | --- | --- |
| 운동 종류 | Cycling/Running/Walking radial 선택 제공 | 기존 radial interaction을 유지하고 선택 결과를 pre-ride summary에 명시한다. |
| Bike 선택 | cycling mode만 존재 | 별도 feature가 아니라 Record 설정의 optional equipment/profile input으로 확장한다. profile이 없을 때 cycling flow는 그대로 시작 가능해야 한다. |
| Start UX | READY drag-to-select, 위치·날씨·추천 route 제공 | 시작 직전 compact confirmation(종목, bike, GPS status, route availability)을 추가하는 방향으로 설계한다. 권한 요청을 시작 동작의 필수 gate로 만들지 않는다. |

## 3. GPS tracking 구조

### 현재 구성

- `RecordLocationManager`는 `CLLocationManagerDelegate`로 권한, 현재 좌표, heading/course, speed를 `RecordLocationState`에 publish한다.
- 정확도는 `kCLLocationAccuracyNearestTenMeters`, distance filter는 10m, heading filter는 5도다.
- 권한 허용 또는 위치 버튼 동작에서 `requestLocation()`을 호출하고 heading update를 시작한다.
- `RecordView`는 `locationManager.state` 변경을 관찰한다. active session일 때 `recordLocationIfNeeded`가 좌표와 speed를 `RecordWorkoutSession.recordingLocation`에 전달한다.
- session은 `RecordRouteCapture`에 좌표를 누적하고 Haversine 거리(0.5m 미만 segment 제외), 현재/최대 속도, 시작/마지막 좌표를 유지한다.

### 현재 한계

1. `RecordLocationManager`에는 `startUpdatingLocation()`/`stopUpdatingLocation()` lifecycle이 없다. 현재 구현은 one-shot location request와 delegate update에 의존하므로, 장시간 기록의 지속 위치 추적 계약이 명시되지 않았다.
2. pause 시간이 별도 누적되지 않는다. `RecordWorkoutSession.elapsedTime`은 `startedAt`부터 현재/종료 시점까지를 계산하므로 pause 구간을 운동 시간에서 제외하지 못한다.
3. background location, accuracy degradation, stale location, outlier filtering, GPS loss/recovery 상태가 없다.
4. heart rate, elevation, cadence는 location/session data model에 입력 경로가 없다.

### 재사용 우선 개선 계획

`RecordLocationManager`를 대체하지 않고 recording-specific lifecycle API를 추가하는 방식으로 확장한다.

```text
RecordView state transition
  ready → active: location manager begins continuous recording updates
  active → paused: location updates pause; active duration is closed
  paused → active: updates resume; a new active duration begins
  active/paused → finished/cancelled: updates stop and final sample is flushed
```

- `RecordLocationState`에 timestamp, horizontal accuracy, altitude, vertical accuracy를 추가할 수 있는 확장 지점을 둔다.
- session에는 active duration, elevation gain, sensor sample summary를 추가하되, `RecordWorkoutSession`의 value-semantic transition API를 유지한다.
- GPS 신뢰도는 `accepted`, `stale`, `lowAccuracy`, `unavailable`처럼 HUD가 표시 가능한 상태로 분리한다.

## 4. Map component 분석

### 현재 구성

- `RecordMapView`는 Mapbox 사용 가능 여부에 따라 `RecordMapboxSurface` 또는 fallback surface를 선택한다.
- Mapbox surface는 추천 route polyline, 현재 위치/heading 표시, recenter trigger, session state에 따른 navigation puck/compass 표현을 관리한다.
- map camera는 현재 위치와 `RecordRouteRecommendation` coordinates를 사용해 launch state를 만든다.

### 현재 한계 및 개선 방향

- 현재 지도 polyline은 `selectedRoute`의 **추천 route**다. `RecordWorkoutSession.capturedRoute`는 지도 입력으로 전달되지 않아 실제 누적 경로는 live map에 그려지지 않는다.
- 개선 시 `RecordMapView`에 optional captured route overlay를 추가하고, 추천 route와 실제 track을 명확히 다른 style로 그린다. 이때 Mapbox surface와 fallback surface 모두 동일한 input contract를 받게 한다.
- active tracking 중에는 user-follow/recenter, paused 상태에는 현재 카메라 유지, finish 상태에는 complete route fit을 적용한다.
- route privacy masking은 Finish/export 단계의 정책으로 두며, raw capture를 Record session 중에 변형하지 않는다.

## 5. Workout session lifecycle

| 상태 | 현재 전이 | 현재 UI | 개선 시 지켜야 할 불변 조건 |
| --- | --- | --- | --- |
| ready | READY radial selection 후 `start` | map + launch control | 위치가 없어도 time-only session을 시작할 수 있다. |
| active | `RecordWorkoutSession.state == .active` | compact/expanded HUD, pause/finish/cancel | accepted GPS sample만 거리/route에 반영한다. |
| paused | active에서 pause | status chip과 resume action | active duration·distance·route를 보존하고 background updates를 중단한다. |
| finished | finish action | summary + save/share/later actions | summary는 immutable snapshot이며 저장은 idempotent해야 한다. |
| cancelled | explicit cancel | session 제거 | UnifiedWorkout/Feed draft를 만들지 않는다. |

현재 `RecordActiveHUDLayout`은 Cycling에서 현재 속도, 평균 속도, 최대 속도, 거리, 시간과 placeholder heart/cadence/grade/elevation을 제공한다. Running/Walking도 pace/speed와 거리·시간을 제공한다. HUD compact/expanded presentation 구조는 목표 Live 화면의 기반으로 재사용한다.

## 6. Live UX 개선 계획

### 목표 metric contract

| Metric | 현재 입력 | 현재 표시 | 목표 data source |
| --- | --- | --- | --- |
| 지도 | 추천 route + 현재 위치 | 제공 | 추천 route와 captured route overlay를 분리 |
| 현재 속도 | `CLLocation.speed` | 제공 | accuracy/timestamp 검증 후 표시 |
| 평균 속도/pace | distance ÷ elapsed | 제공 | active duration 기준으로 계산 |
| 거리 | `RecordRouteCapture` Haversine 합 | 제공 | outlier filtering 후 누적 |
| 시간 | `startedAt` 기준 | 제공 | paused duration 제외 |
| 심박 | 없음 | `--` placeholder | HealthKit/device sensor adapter, unavailable state 유지 |
| 고도 | 없음 | `0` 또는 `--` placeholder | CLLocation altitude/vertical accuracy 기반 elevation builder |

### 화면 구조

1. map-first canvas와 현재 compact HUD 구조를 유지한다.
2. compact HUD에는 시간과 sport-specific primary metric(자전거는 speed, 러닝은 pace)을 유지한다.
3. expanded HUD에는 거리, 평균 speed/pace, heart rate, elevation을 포함한 2-column metric grid를 사용한다.
4. GPS/heart/elevation이 unavailable이면 값을 추정하거나 mock으로 채우지 않고 명시적 unavailable state를 표시한다.
5. pause/finish/cancel actions는 existing session transition을 호출하는 단일 control strip으로 유지한다.

## 7. Finish, 저장, Activity/Feed/Recovery 연결

### 현재 finish/save flow

```text
finished RecordWorkoutSession
  → RecordWorkoutSummaryBuilder
  → RecordWorkoutSaver
      → SwiftDataUnifiedWorkoutStore.saveWorkout(UnifiedWorkout)
      → SwiftDataWorkoutRoutePersistenceStore.saveRoute(WorkoutRoute), when captured route exists
  → savedWorkoutForShare
      ├─ later: onSaveComplete → Activity tab
      └─ shareToFeed: RecordShareDraftCoordinator → FileFeedShareDraftStore → Feed tab
```

- `RecordWorkoutSaveMapper`는 local source의 `UnifiedWorkout`을 만들고, distance/duration으로 average speed를 계산한다.
- `RecordWorkoutSummary`는 시작/종료/거리/route 존재 여부를 제공하며 Finish HUD에 표시된다.
- Feed 공유는 remote post가 아니라 local `FeedShareDraft`를 생성한다. Feed data source가 draft를 병합해 보여 준다.
- Activity는 `SwiftDataUnifiedWorkoutStore.fetchRecentWorkouts`로 저장 workout을 읽는 진입점을 이미 갖고 있다.
- Recovery는 `UnifiedWorkoutRecoveryPreviewProvider`를 통해 저장된 `UnifiedWorkout`을 계산 input으로 읽을 수 있다.

### 현재 한계

- Finish summary에는 route preview와 speed 중심의 rich summary가 아직 분리 component로 존재하지 않는다.
- 저장 시 heart rate와 elevation은 `nil`로 persist된다.
- Recovery는 저장 결과를 읽을 수 있지만, Record finish 직후 recovery impact를 계산·표시하거나 daily snapshot을 갱신하는 direct handoff는 없다.
- Feed draft의 route preview는 저장된 actual route를 직접 읽지 않고 운동 거리와 fallback style로 구성된다.

### Finish 개선 계획

1. `RecordWorkoutSummary`를 source of truth로 유지하고, `RecordFinishReadModel`을 별도 projection으로 만든다.
2. finish view는 summary hero, captured route preview, metrics, recovery impact preview, share/later actions 순서로 조립한다.
3. 저장 성공 뒤에만 Feed draft 또는 Recovery preview를 생성한다. 저장 실패 시 기존 retry/error behavior를 유지하고 secondary side effect를 실행하지 않는다.
4. Recovery 연결은 `UnifiedWorkout`을 입력으로 하는 existing provider를 재사용한다. Recovery 도메인 계산 규칙을 Record에 복제하지 않는다.
5. Feed 연결은 `RecordShareDraftCoordinator`를 유지하되, actual persisted route가 있을 때 route preview payload가 이를 참조하도록 확장한다.

## 권장 이행 순서

1. **Data/lifecycle foundation**: continuous location lifecycle, active duration, sample validation을 session 및 location manager에 추가한다.
2. **Map foundation**: captured route overlay와 finish route fit을 추가한다.
3. **Sensor foundation**: heart/elevation adapter 및 unavailable state를 추가한다.
4. **Before Ride UX**: existing READY interaction 위에 optional bike/profile 및 start confirmation을 얹는다.
5. **Finish projection**: summary/route/recovery read model을 구성하고 저장 뒤 Feed/Recovery handoff를 연결한다.
6. **QA**: permission denied, no GPS, pause/resume, background/foreground, map token missing, save failure, route persistence failure, Feed draft failure를 검증한다.

각 단계는 `RecordWorkoutSessionTests`, `RecordWorkoutSaveFlowTests`, `RecordMapFoundationTests`, `RecordLaunchPlanTests`를 유지·확장한다. 실제 GPS/HealthKit/device QA는 별도 승인 후에만 수행한다.

## 완료 기준

- Before Ride, Live, Finish의 현재 책임과 확장 책임이 분리되어 있다.
- 기존 fullScreenCover, session, Mapbox/fallback map, SwiftData 저장, Feed draft, Recovery provider 재사용 경로가 기록되어 있다.
- 지속 GPS, 실제 route overlay, pause duration, heart/elevation가 구현 전 해결해야 할 foundation gap으로 명시되어 있다.
- 이번 문서 작성 외에 Record/Navigation/Recovery production 코드는 변경하지 않는다.
