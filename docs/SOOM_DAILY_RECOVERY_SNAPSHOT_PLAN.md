# SOOM Daily Recovery Snapshot Plan

## A. Purpose

Daily Recovery Snapshot은 특정 날짜에 계산된 `RecoverySummary` 결과를 보관하기 위한 일별 기록이다. 현재 Recovery 화면은 “오늘 상태”를 계산해 보여주지만, Timeline, 주간 흐름, 장기 컨디션 분석은 하루하루의 결과가 남아 있어야 안정적으로 확장할 수 있다.

Snapshot을 저장하는 이유:

- Recovery Timeline을 mock 데이터에서 실제 일별 회복 기록으로 전환한다.
- 사용자가 최근 며칠 동안 회복 점수가 어떻게 이어졌는지 이해할 수 있게 한다.
- 주간 평균, 회복 추세, 피로 누적 흐름을 계산할 기반을 만든다.
- AI Coach가 “이번 주는 회복 흐름이 안정적이었어요” 같은 주간 요약을 만들 수 있게 한다.
- HealthKit, check-in, 운동 기록이 늘어나도 특정 날짜의 화면 결과를 재현할 수 있게 한다.

## B. Snapshot Data Fields

v1 후보 필드:

- `id`: snapshot 고유 식별자
- `date`: snapshot 기준 날짜. 하루 단위 비교를 위해 start-of-day 기준으로 정규화한다.
- `score`: 해당 날짜의 회복 점수
- `status`: 좋음, 보통, 주의, 데이터 부족 등 상태 라벨
- `recommendation`: 해당 날짜의 추천 행동 요약
- `coachMessage`: 해당 날짜의 코치 메시지
- `explanation`: “왜 이런 상태인지”를 설명하는 짧은 문장
- `dataQuality`: mock, estimated, high confidence 등 데이터 품질
- `activityCount`: 계산에 사용된 최근 활동 수
- `checkInId`: 해당 날짜 또는 최신 check-in과 연결할 수 있는 선택 ID
- `createdAt`: 최초 생성 시각
- `updatedAt`: 마지막 갱신 시각

향후 후보 필드:

- `trendText`: 화면에 표시한 점수 변화 요약
- `insightSummaries`: 주요 insight 1~2개 요약
- `sourceVersion`: 계산 공식 또는 provider 버전
- `inputHash`: 같은 입력으로 중복 snapshot을 만들지 않기 위한 lightweight fingerprint

## C. Source of Truth

역할 분리:

- `RecoveryCalculator`: 현재 입력을 바탕으로 오늘의 `RecoverySummary`를 계산한다.
- `DailyRecoverySnapshot`: 특정 날짜의 계산 결과를 저장한다.
- `RecoveryTimelineBuilder`: 현재 mock 기반 Timeline을 만들지만, 향후 snapshot store에서 읽은 기록으로 Timeline entry를 만든다.

정책:

- 현재 회복 점수의 source of truth는 여전히 `RecoveryCalculator` 결과다.
- Snapshot은 과거 결과 보관용이며, 현재 점수 계산 공식에 개입하지 않는다.
- Timeline은 mock → snapshot 기반으로 전환하되, `RecoveryCalculator` 로직은 변경하지 않는다.
- Snapshot 저장소가 비어 있으면 Timeline은 빈 상태 또는 mock fallback 정책을 별도로 정한다.

## D. Generation Timing

Snapshot 생성 후보 시점:

- 앱 실행 시: 날짜가 바뀌었고 오늘 snapshot이 없으면 생성 후보
- RecoveryView 진입 시: 현재 `RecoverySummary`가 로드된 뒤 오늘 snapshot upsert 후보
- Check-in 저장/수정 후: coachMessage, insight, explanation 개인화가 바뀔 수 있으므로 오늘 snapshot 갱신 후보
- 운동 기록 변경 후: activity 기반 score, trend, recommendation이 바뀔 수 있으므로 snapshot 재생성 후보
- 하루 1회 자동 생성: 백그라운드 작업 또는 앱 실행 시점 기반 후보

초기 구현 권장:

1. RecoveryView 진입 시 현재 summary를 계산한다.
2. 오늘 날짜 snapshot이 없으면 생성한다.
3. 이미 있으면 `updatedAt`만 갱신할지, summary 필드를 overwrite할지 정책을 정한다.
4. Check-in 저장/수정/삭제 후 snapshot 재생성은 v2에서 결정한다.

## E. Storage Strategy

SwiftData 기반 후보:

- `DailyRecoverySnapshotRecord`
  - SwiftData `@Model`
  - `date`에 대한 uniqueness 정책 검토
  - `score`, `status`, `recommendation`, `coachMessage`, `explanation`, `dataQuality`, `activityCount`, `checkInId`, `createdAt`, `updatedAt` 저장

Store 후보:

- `DailyRecoverySnapshotStore`
  - `fetchRecentSnapshots(days:)`
  - `fetchSnapshot(date:)`
  - `upsertSnapshot(_:)`
  - `deleteSnapshot(id:)`, 향후 필요 시
- `SwiftDataDailyRecoverySnapshotStore`
  - SwiftData 구현체

Timeline 전환 방향:

- 현재 `RecoveryTimelineBuilder`는 mock generator 역할이다.
- Snapshot store가 생기면 `RecoveryTimelineBuilder` 또는 별도 mapper가 `[DailyRecoverySnapshot]`을 `[RecoveryTimelineEntry]`로 변환한다.
- UI 컴포넌트인 `RecoveryTimelineCard`는 데이터 출처를 알지 않게 유지한다.

## F. Safety Policy

Snapshot은 과거 회복 상태를 보관하기 위한 기록이며, 현재 score 계산 로직을 바꾸지 않는다.

안전 정책:

- `RecoveryCalculator` 공식은 Snapshot 도입과 무관하게 유지한다.
- Snapshot 저장 실패는 Recovery 화면 표시 실패로 이어지지 않게 한다.
- Snapshot은 의료 기록처럼 표현하지 않고, 운동 컨디션 참고 기록으로 다룬다.
- Check-in 삭제/수정 시 과거 snapshot을 자동으로 재작성할지 여부는 v2에서 결정한다.
- 운동 기록이 나중에 수정되거나 삭제될 때 과거 snapshot을 재계산할지, 당시 기록을 보존할지도 v2 정책으로 둔다.
- Formula version이 바뀌면 기존 snapshot을 일괄 재계산하지 않고, `sourceVersion` 같은 필드로 구분하는 방향을 검토한다.

## G. Future Expansion

Snapshot 기반으로 확장할 수 있는 기능:

- 최근 7일 회복 점수 평균
- 최근 30일 회복 추세
- 고부하 이후 회복 속도 분석
- 운동 종목별 회복 패턴
- AI Coach weekly summary
- Check-in 기반 컨디션 변화 요약
- HealthKit HRV, sleep, resting heart rate 통합
- 회복 점수와 실제 운동 성과 간 관계 분석
- 서버/iCloud 동기화 후 기기 간 Recovery Timeline 유지

## H. Implementation Status

Phase 1 완료:

- Snapshot 데이터 계약 문서화
- Timeline이 향후 snapshot 기반으로 전환된다는 문서 연결

Phase 2 완료:

- `DailyRecoverySnapshot` 도메인 모델 추가
- `DailyRecoverySnapshotRecord` SwiftData `@Model` 추가
- `DailyRecoverySnapshotMapper` 추가
- `DailyRecoverySnapshotStore` 프로토콜과 `SwiftDataDailyRecoverySnapshotStore` 1차 구현
- 앱 전역 `ModelContainer`에 `DailyRecoverySnapshotRecord` 등록
- in-memory SwiftData 기반 store 테스트 추가

Phase 3 완료:

- `RecoveryTimelineBuilder`가 `DailyRecoverySnapshotStore`를 주입받아 최근 snapshot을 읽는다.
- `DailyRecoverySnapshot`은 `RecoveryTimelineEntry`로 변환되어 `RecoveryTimelineCard`에 전달된다.
- Production `RecoveryViewContainer`는 `SwiftDataDailyRecoverySnapshotStore`를 Timeline builder에 주입한다.
- `RecoveryViewModel.reload()`와 `load()` 재진입 시 Timeline도 snapshot source of truth에서 다시 읽는다.
- 저장된 snapshot이 없으면 fake history를 만들지 않고 “아직 회복 흐름 기록이 없어요.” empty state를 보여준다.

Phase 4 완료:

- `DailyRecoverySnapshotWriter`가 `RecoverySummary`를 오늘 날짜의 `DailyRecoverySnapshot`으로 변환해 저장한다.
- Production `RecoveryViewContainer`는 Timeline용 `SwiftDataDailyRecoverySnapshotStore`를 writer에도 주입해 같은 source of truth를 사용한다.
- `RecoveryViewModel`은 summary와 latest check-in 개인화를 적용한 뒤 오늘 snapshot 저장을 시도한다.
- 같은 날짜 snapshot은 store의 same-day upsert 정책으로 중복 생성하지 않는다.
- snapshot 저장 실패는 Recovery 화면 로드 실패로 전파하지 않는다.
- snapshot 저장 후 Timeline을 다시 읽어 오늘 entry가 바로 반영되게 한다.

Phase 5 완료:

- `WeeklyRecoverySummary` 도메인 모델을 추가했다.
- `WeeklyRecoverySummaryBuilder`가 최근 7일 `DailyRecoverySnapshot`을 읽어 평균 점수, 최고/최저 점수, 주간 trend direction, 코치 인사이트, 다음 주 추천을 만든다.
- `WeeklyCoachSummaryCard`가 Recovery 화면의 Timeline 아래에서 “이번 주 회복 흐름”을 보조 해석 카드로 표시한다.
- Weekly Summary는 snapshot을 읽는 interpretation layer이며, `RecoveryCalculator`의 score/status/recommendation 계산에는 관여하지 않는다.

현재 의도적으로 보류한 것:

- `RecoveryCalculator` score/status/recommendation 로직은 변경하지 않았다.
- Check-in 수정/삭제 후 snapshot 재생성 정책은 아직 구현하지 않았다.
- LLM/ML 기반 주간 요약은 도입하지 않았다.

v1에서는 Snapshot 저장, Timeline 표시 전환, Recovery 진입 시 오늘 snapshot 자동 저장, Snapshot 기반 Weekly Summary까지 준비한다. Check-in 수정/삭제 후 재생성 정책과 HealthKit/CloudKit 동기화는 별도 단계에서 진행한다.
