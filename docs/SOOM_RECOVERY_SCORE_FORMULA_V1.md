# SOOM Recovery Score Formula v1

## A. Purpose

SOOM Recovery Score는 사용자가 오늘의 훈련 준비도와 회복 상태를 쉽게 이해하도록 돕는 지표다. 점수는 의료적 진단이 아니라 최근 운동 기록을 바탕으로 한 회복 가이드이며, 사용자가 오늘 강도를 올려도 되는지, 가볍게 움직이는 편이 좋은지, 휴식을 우선해야 하는지를 빠르게 판단하도록 돕는다.

핵심 정의:

- 오늘 훈련 준비도와 회복 상태를 이해하기 쉽게 보여주는 지표
- 최근 운동 부하, 체감 강도, 휴식일 흐름을 단순 규칙으로 요약한 MVP 점수
- 사용자의 불안을 키우기보다 다음 행동을 부드럽게 제안하는 코칭 신호

## B. Current Inputs v1

현재 `RecoveryCalculator`가 사용하는 입력은 `RecoveryActivity` 배열이다. 이 배열은 현재 mock 또는 local snapshot 기반이며, HealthKit, DB, 서버에 직접 연결되어 있지 않다.

현재 사용하는 입력:

- 최근 7일 운동 기록
- 최근 3일 `trainingLoad` 평균
- 최근 7일 `relativeEffort` 누적
- `averageHeartRate` 흐름
- 휴식일 수

입력 필드:

- `workoutType`: ride, run, swim, brick
- `durationMinutes`: 운동 시간
- `distanceKm`: 거리
- `averageHeartRate`: 평균 심박
- `relativeEffort`: 체감 강도 또는 세션 난이도
- `trainingLoad`: 세션 부하 추정치
- `completedAt`: 완료 시각

## C. Current Output

`RecoveryCalculator.calculateSummary(from:)`는 `RecoverySummary`를 반환한다.

현재 출력:

- `score`: 45...95 범위의 회복 점수. 운동 기록이 없을 때는 72.
- `status`: 좋음, 보통, 주의, 또는 데이터 부족.
- `description`: 점수의 이유를 설명하는 짧은 문장.
- `recommendation`: 오늘 권장 행동 요약.
- `coachMessage`: SOOM AI 코치 메시지.
- `recommendationCard`: 추천 행동 카드 데이터.
- `trends`: 운동 부하, 피로도, 평균 심박 추세.
- `insights`: 운동 기록 기반 추정, 부하 안정/주의, 최근 운동, 휴식일 부족 등.
- `lastUpdated`: 계산 기준 시각.
- `dataQuality`: 현재 activity 기반 계산은 `estimated`, 정적 mock summary는 `mock`.

## D. Current MVP Rules

현재 v1은 설명 가능한 규칙 기반 MVP다. 생리학적으로 검증된 알고리즘이 아니라, 제품 초기 단계에서 회복 흐름을 일관되게 표현하기 위한 간단한 기준이다.

### Empty Data Rule

운동 기록이 없으면 점수 계산을 하지 않고 중립 요약을 반환한다.

- `score`: 72
- `status`: 데이터 부족
- `dataQuality`: estimated
- `recommendation`: 가벼운 활동 제안
- `trends`: 기록 부족 상태
- `insights`: 운동 기록이 더 필요하다는 안내

### Score Formula

운동 기록이 있으면 최근 활동을 기준으로 다음 값을 계산한다.

- `recentLoadAverage`: 최근 3일 `trainingLoad` 평균
- `effortSum`: 최근 7일 `relativeEffort` 합계
- `restDays`: 최근 7일 중 운동 기록이 없는 날짜 수

현재 점수식:

```text
rawScore = 88
rawScore -= Int(recentLoadAverage / 12)
rawScore -= Int(Double(effortSum) / 55)
rawScore += min(restDays, 3) * 4
score = clamp(rawScore, 45, 95)
```

규칙 해석:

- 최근 3일 `trainingLoad` 평균이 높으면 점수 감소
- 최근 7일 `relativeEffort` 누적이 높으면 점수 감소
- 휴식일이 있으면 점수 증가
- 휴식일 보정은 최대 3일까지만 반영
- 극단값은 45...95 범위로 제한

### Status Label Rule

현재 코드 기준 status label:

- `82...95`: 좋음
- `68...81`: 보통
- `45...67`: 주의
- 운동 기록 없음: 데이터 부족

### Trend Rules

현재 trend는 점수 계산과 별도로 사용자에게 흐름을 보여주기 위한 정보다.

- 운동 부하: 최근 7일 `trainingLoad` 합계와 최근 3일 평균 표시
- 피로도: 최근 부하, 체감 강도, 휴식일 기반 보조 점수
- 평균 심박: 전체 평균 심박과 최근 3일 평균 심박 차이 표시

### Insight Rules

현재 insight는 다음 기준으로 생성된다.

- 모든 activity 기반 계산에는 “운동 기록 기반 추정” insight를 포함
- `recentLoadAverage > 85` 또는 `effortSum > 220`이면 부하 누적 주의
- 그 외에는 훈련 부하 안정
- 마지막 운동 기록이 있으면 최근 운동 요약 추가
- `restDays <= 1`이면 휴식일 부족 안내 추가

## E. Interpretation Guide

제품 문구와 UI에서는 점수를 너무 딱딱한 판정처럼 보이지 않게 사용한다. 아래 구간은 사용자 이해를 돕는 가이드이며, 현재 코드의 status label 기준은 D 섹션의 `Status Label Rule`을 따른다.

- 85~95: 회복 양호 / 훈련 가능
- 70~84: 보통 / 가벼운 훈련 가능
- 55~69: 주의 / 강도 조절 필요
- 45~54: 회복 우선

표현 예:

- “오늘은 Z2 라이딩 40분 또는 가벼운 조깅을 추천해요.”
- “오늘은 완전 휴식 또는 30분 회복 라이딩을 추천해요.”
- “최근 부하와 체감 강도가 함께 올라갔습니다.”

피해야 할 표현:

- “위험합니다.”
- “질병 가능성이 있습니다.”
- “훈련하면 안 됩니다.”
- “의학적으로 회복되지 않았습니다.”

## F. Limitations

v1은 초기 제품 경험을 위한 단순 추정이다. 다음 한계를 명확히 유지한다.

- HRV 미반영
- 수면 시간/품질 미반영
- 휴식기 심박 장기 기준선 미반영
- 주관적 피로도 체크인 미반영
- 운동 종목별 부하 차이 단순화
- `trainingLoad`는 현재 임시 추정값
- 사용자별 장기 기준선 미반영
- 생리학적/의학적 진단 정확성을 목표로 하지 않음

## G. Future v2 Inputs

v2에서는 다음 입력을 점진적으로 추가한다.

- HRV
- resting heart rate trend
- sleep duration / quality
- TRIMP
- acute/chronic load ratio
- subjective fatigue check-in
- wearable data confidence
- 장기 개인 기준선
- 종목별 부하 보정
- 파워/심박 존 기반 강도 분포

확장 방향:

- `RecoveryActivity`는 앱 내부 운동 기록과 HealthKit workout을 연결하는 최소 입력으로 유지한다.
- HRV, 수면, 휴식기 심박, 주관 피로도는 별도 input model로 분리한 뒤 `CombinedRecoveryDataProvider`에서 병합한다.
- 점수 계산은 `RecoveryCalculator` 또는 향후 `RecoveryScoreEngine` 계층에서 테스트 가능한 순수 계산으로 유지한다.

### Subjective Check-in Candidate

사용자가 직접 입력하는 subjective check-in은 v2 입력 후보로 둔다. v1 `RecoveryCalculator`에는 아직 연결하지 않는다. Check-in 입력 흐름과 문구 기준은 [SOOM_CHECKIN_UX_SPEC.md](SOOM_CHECKIN_UX_SPEC.md)를 v2 입력 UX 기준으로 삼는다.

후보 입력:

- fatigueLevel: 피로도, 1...5
- sleepQuality: 수면감, 1...5
- muscleSoreness: 근육통, 1...5
- moodLevel: 기분/컨디션, 1...5
- note: 선택 메모

향후 반영 방향:

- 피로도와 근육통이 높으면 recovery score를 낮추는 방향으로 반영한다.
- 수면감과 moodLevel이 안정적이면 score 하락을 완화하는 보조 신호로 사용한다.
- HealthKit 수면/HRV와 사용자의 직접 입력이 충돌할 경우 `dataQuality`와 설명 문구로 신뢰도를 투명하게 보여준다.
- check-in 입력은 진단 질문이 아니라 짧고 부담 없는 컨디션 기록으로 설계한다.

현재 준비 구조:

- `CombinedRecoveryDataProvider`는 activity와 check-in을 함께 fetch할 수 있다.
- `RecoveryInputContext`는 `activities`, `checkIns`, `generatedAt`을 함께 담는다.
- v1 score는 여전히 activity 기반 `RecoveryCalculator.calculateSummary(from:)` 결과만 사용한다.
- check-in이 존재해도 v1 score, status, recommendation은 변경하지 않는다.
- v1.5에서는 `RecoveryCoachMessagePersonalizer`가 최신 check-in을 참고해 coach message 문장만 개인화할 수 있다.
- v1.5에서는 `RecoveryInsightPersonalizer`가 최신 check-in을 참고해 insight 1개를 보조 맥락으로 추가할 수 있다.
- 이 개인화는 score formula에 포함되지 않으며, `RecoveryCalculator`의 score/status 계산 규칙을 변경하지 않는다.

### Explainable Recovery

SOOM은 사용자가 점수만 보고 판단하게 하지 않고, “왜 이런 회복 상태가 나왔는지”를 짧게 이해할 수 있게 한다.

v1 Explanation 원칙:

- `RecoveryExplanationBuilder`는 `RecoverySummary`와 최신 check-in을 읽어 설명 문장만 만든다.
- `RecoveryCalculator`의 score/status/recommendation 계산은 변경하지 않는다.
- 설명은 한 번에 1개의 핵심 이유를 우선한다.
- supporting bullet은 최대 2개로 제한한다.
- 수식이나 세부 수치를 과하게 노출하지 않고, 운동 부하, 휴식 리듬, 체감 피로, 수면감처럼 사용자가 이해하기 쉬운 이유로 표현한다.
- check-in 기반 설명은 coach/insight 개인화와 같은 보조 맥락이며, v1 score formula에는 포함하지 않는다.

설명 예:

- “최근 운동 부하가 높게 유지되고 있어요.”
- “휴식일이 포함되어 회복 리듬이 안정적으로 유지되고 있어요.”
- “최근 컨디션 기록에서 피로감이 높게 나타났어요.”

### Historical Timeline

Recovery Timeline은 최근 회복 상태의 흐름을 이해하기 위한 historical interpretation layer다. 현재 MVP에서는 저장된 `DailyRecoverySnapshot`을 읽어 최근 흐름을 표시한다.

v1 Timeline 원칙:

- `RecoveryTimelineBuilder`는 최근 며칠의 회복 점수, 상태, 짧은 설명, 추천 요약을 만든다.
- Timeline은 `RecoveryCalculator`의 score/status/recommendation 계산에 관여하지 않는다.
- 복잡한 라인 차트나 예측 모델 대신 최근 3~5일의 흐름을 세로 리스트로 보여준다.
- 점수 범위는 Formula v1의 내부 clamp 범위인 45...95를 유지한다.
- snapshot이 없으면 fake history를 만들지 않고 부드러운 empty state를 보여준다.
- Daily Recovery Snapshot 전환 계획은 [SOOM_DAILY_RECOVERY_SNAPSHOT_PLAN.md](SOOM_DAILY_RECOVERY_SNAPSHOT_PLAN.md)를 기준으로 한다.

표현 예:

- “운동 부하가 조금 올라와 회복 여유가 줄었어요.”
- “휴식일이 포함되어 회복 흐름이 안정적이었어요.”
- “훈련 리듬은 유지됐지만 완전한 휴식은 부족했어요.”

### Weekly Coach Summary

Weekly Coach Summary는 최근 7일 `DailyRecoverySnapshot`을 기반으로 주간 회복 흐름을 해석하는 보조 레이어다. 이 기능은 score calculation이 아니라 interpretation layer다.

v1 Weekly Summary 원칙:

- `WeeklyRecoverySummaryBuilder`는 최근 snapshot의 평균 점수, 최고/최저 점수, 후반부 흐름, 간단한 코치 인사이트를 만든다.
- `WeeklyCoachSummaryCard`는 Recovery 화면의 Timeline 아래에서 “이번 주 회복 흐름”을 1개 카드로 요약한다.
- Weekly Summary는 `RecoveryCalculator`의 score/status/recommendation 계산을 변경하지 않는다.
- LLM/ML 요약은 사용하지 않고, 설명 가능한 규칙 기반 문장만 사용한다.
- 의료/진단 표현 대신 “흐름”, “리듬”, “추천” 중심의 부드러운 문장을 사용한다.

## H. Safety / UX Principle

SOOM Recovery Score는 의료 진단처럼 표현하지 않는다. 사용자가 자신의 몸 상태를 더 잘 이해하도록 돕는 추정형 코칭 지표로 다룬다.

문장 원칙:

- “추정”, “추천”, “가이드” 표현을 사용한다.
- 단정 대신 가능성과 방향성을 말한다.
- 사용자가 불안해하지 않도록 부드럽고 행동 가능한 문장으로 표현한다.
- 점수가 낮을 때도 실패나 경고가 아니라 회복 전략으로 안내한다.
- 고통, 어지러움, 흉통 등 건강 이상 신호는 앱 점수보다 전문가 상담과 휴식을 우선하도록 별도 정책에서 다룬다.

## Test Alignment

Formula v1에서 반드시 회귀 테스트로 유지할 규칙:

- 운동 기록이 없으면 72점과 “데이터 부족”을 반환한다.
- 7일 연속 고부하 fixture는 회복 점수를 낮추고 회복/강도 조절 메시지를 만든다.
- 휴식일이 포함된 moderate load fixture는 지나치게 낮은 점수로 떨어지지 않는다.
- 점수는 45보다 낮아지지 않고 95보다 높아지지 않는다.
- activity 입력이 있으면 trends와 insights가 생성된다.

테스트 또는 알고리즘을 변경할 때는 이 문서를 먼저 확인하고, 문서/테스트/코드가 같은 방향을 보도록 함께 갱신한다.
