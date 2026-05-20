# SOOM Morning Check-in Flow v1

## A. Purpose

Morning Check-in은 사용자가 하루에 한 번 SOOM을 열 이유를 만드는 Daily Readiness Loop다. 목표는 아침에 앱을 열자마자 “오늘 운동해도 되는가?”를 부담 없이 확인하고, 짧은 컨디션 기록을 통해 Recovery 코칭 문장을 더 개인화하는 것이다.

Morning Check-in은 새로운 점수 계산이 아니다. 기존 `RecoverySummary`, `DailyReadinessState`, `RecoveryCheckIn` 흐름을 활용해 사용자가 오늘의 몸 상태, 이유, 추천 행동을 빠르게 이해하도록 돕는다.

목적:

- 사용자가 하루 1회 SOOM을 여는 명확한 이유를 만든다.
- Daily Readiness를 통해 오늘의 접근 방식을 3초 안에 이해하게 한다.
- Check-in을 10초 안에 끝나는 가벼운 루틴으로 만든다.
- 기록 후 Recovery coach message와 insight가 사용자의 체감 컨디션에 맞게 갱신되는 피드백 루프를 만든다.
- 의료 설문이나 진단처럼 보이지 않고, 운동 컨디션을 조용히 정리하는 경험을 제공한다.

## B. User Flow

권장 v1 흐름:

1. 앱 실행
2. Home 또는 Recovery 상단에서 Daily Readiness 확인
3. 오늘 컨디션 기록 여부 확인
4. 오늘 기록이 없으면 Check-in을 부드럽게 유도
5. 사용자가 기록하거나 건너뛰기 선택
6. 기록 후 Recovery 화면으로 돌아오면 latest check-in 기반 coach message와 insight 개인화 갱신
7. 사용자는 오늘 추천 행동을 확인하고 운동/회복 결정을 내림

핵심은 사용자를 입력 화면으로 밀어 넣는 것이 아니라, “오늘 상태를 이해하는 흐름” 안에서 자연스럽게 기록을 제안하는 것이다.

Daily Readiness가 핵심 상태를 먼저 말하고, Morning Prompt는 그 상태를 더 개인화하기 위한 가벼운 상호작용으로 뒤따른다. 두 요소가 같은 무게로 경쟁하면 아침 루프가 할 일 목록처럼 느껴질 수 있으므로, prompt는 compact한 문장과 낮은 대비의 CTA를 사용한다.

## C. Entry Points

### Home

Home은 가장 자연스러운 아침 진입점이다. Daily Readiness 요약과 “오늘 컨디션 기록하기” CTA를 짧게 제공할 수 있다.

### Recovery

Recovery는 Morning Check-in의 기준 화면이다. Daily Readiness, Recovery Score, Coach Message, Recommendation을 통해 오늘 상태와 행동을 확인한다.

### Push Notification 후보

v2 이후 아침 리마인더를 제공할 수 있다. 문구는 강요가 아니라 루틴 제안이어야 한다.

예:

- “오늘 몸 상태를 가볍게 확인해볼까요?”
- “10초만 기록하면 오늘 추천을 더 맞춰볼게요.”

### Widget 후보

Daily Readiness 상태와 오늘 check-in 여부를 짧게 보여준다. 입력은 앱으로 진입해 완료하는 구조가 안전하다.

### Apple Watch 후보

향후 Watch에서 1...5 check-in을 빠르게 입력하거나, iPhone Recovery 화면으로 이어지는 진입점을 제공할 수 있다.

## D. UX Principle

Morning Check-in은 짧고 선택 가능해야 한다.

원칙:

- 10초 이내 완료를 목표로 한다.
- 하루 1회 아침 루틴을 기본으로 한다.
- 사용자가 건너뛸 수 있어야 한다.
- 기록하지 않아도 Recovery 화면은 정상 동작한다.
- 의료 설문, 건강 진단, 위험 경고처럼 보이지 않는다.
- “평가”가 아니라 “오늘 몸 상태를 남기는” 경험으로 표현한다.
- 입력 후에는 오늘 행동으로 이어져야 한다.
- 연속 기록 실패를 벌점, 실패, 결핍처럼 표현하지 않는다.

## E. State Rules

Morning Check-in v1은 다음 상태를 기준으로 화면 문구와 CTA를 결정한다.

### notCheckedInToday

오늘 check-in 기록이 없는 상태다.

권장 UX:

- Daily Readiness 아래 또는 관리 액션 영역에서 가볍게 기록을 제안한다.
- “10초면 충분해요.” 같은 짧은 보조 문구를 사용한다.
- 기록하지 않아도 추천을 볼 수 있음을 암시한다.

### checkedInToday

오늘 check-in 기록이 있는 상태다.

권장 UX:

- `CheckInSummaryCard`로 최신 컨디션을 보여준다.
- coach message와 insight는 latest check-in 기준으로 개인화될 수 있다.
- 사용자가 다시 기록하거나 수정할 수 있지만, v1의 기본 루프는 하루 1회 기록을 중심으로 둔다.

### skippedToday

사용자가 오늘 기록을 명시적으로 건너뛴 상태다. v1에서는 `MorningCheckInSkipStore`가 UserDefaults에 오늘 skip 날짜만 저장하며, check-in history에는 남기지 않는다. 날짜가 바뀌면 skip은 자동으로 무효가 되고 다음 날 prompt를 다시 보여줄 수 있다.

권장 UX:

- 그날 다시 과도하게 묻지 않는다.
- 기록하지 않아도 Recovery 추천이 계속 동작한다고 안내한다.

### insufficientData

운동 기록 또는 snapshot 데이터가 부족해 Recovery 해석 신뢰도가 낮은 상태다.

권장 UX:

- check-in만으로 점수를 대체하지 않는다.
- “데이터가 쌓이면 더 자연스럽게 볼 수 있어요.”처럼 부드럽게 설명한다.
- Daily Readiness는 관찰/가벼운 활동 중심으로 표현한다.

### healthKitNotConnected

HealthKit 연결이 없어 실제 운동 기록 기반 해석이 제한될 수 있는 상태다.

권장 UX:

- HealthKit 연결은 Recovery 핵심 카드가 아니라 하단 관리 액션에 둔다.
- 연결하지 않아도 앱을 사용할 수 있음을 유지한다.
- read-only 정책을 짧게 설명한다.

## F. Copy System

Morning Check-in 문구는 조용하고 행동 가능한 톤을 사용한다.

권장 카피:

- “오늘 몸 상태를 가볍게 확인해볼까요?”
- “10초면 충분해요.”
- “기록하지 않아도 괜찮아요.”
- “오늘은 강도보다 리듬을 먼저 볼게요.”
- “몸이 무겁다면 목표를 조금 낮춰도 좋아요.”
- “기록하면 오늘 코칭 문장을 조금 더 맞춰볼게요.”

피해야 할 카피:

- “반드시 입력해야 합니다.”
- “건강 상태가 위험합니다.”
- “정확한 진단을 위해 필요합니다.”
- “기록하지 않으면 분석이 불완전합니다.”

## G. Data Rules

v1 데이터 정책:

- 하루 1회 아침 check-in을 기본 사용 루프로 둔다.
- 같은 날 여러 번 입력할 수는 있지만, Recovery 개인화에는 최신 check-in만 사용한다.
- History에는 모든 check-in 기록을 보관한다.
- 수정/삭제는 사용자의 기록 통제권을 위해 유지한다.
- check-in은 v1.5에서 coach message와 insight 개인화에만 사용한다.
- Recovery score, status, recommendation은 check-in만으로 변경하지 않는다.
- Morning Check-in prompt 상태는 별도 구현 전까지 UI 정책으로만 다루고, score 계산에 개입하지 않는다.

같은 날 여러 번 입력 정책 후보:

- v1 기본: 여러 번 저장 가능, 최신 기록만 Recovery 개인화에 사용
- v2 후보: 아침 기록을 기본으로 하고, 운동 후 기록은 별도 session context로 분리
- v3 후보: morning, post-workout, evening check-in을 다른 목적의 신호로 분리

## H. Future Expansion

v2 후보:

- Morning reminder
- Home 상단 Daily Readiness prompt
- Widget에서 오늘 준비 상태 확인
- Check-in streak 또는 루틴 지속성 표시
- HealthKit 연결 상태에 따른 부드러운 안내

v3 후보:

- Apple Watch complication
- AI Coach morning briefing
- 주간 컨디션 리듬 요약
- 수면, HRV, 운동 부하, subjective check-in 결합
- 대회 일정과 훈련 계획을 반영한 아침 추천

확장 시에도 Morning Check-in은 SOOM의 핵심 원칙을 유지해야 한다. 사용자를 더 바쁘게 만드는 기능이 아니라, 오늘 몸 상태를 더 쉽게 이해하고 더 나은 운동 결정을 하게 돕는 가벼운 루프여야 한다.

## I. Prompt MVP Status

Morning Check-in Prompt MVP에서는 Recovery 화면에 오늘 check-in 여부를 기준으로 가벼운 기록 유도 카드를 표시한다.

구현 상태:

- `MorningCheckInState`: morning loop 상태를 표현한다.
- `MorningCheckInStateBuilder`: 최신 check-in, 오늘 날짜, 오늘 skip 여부를 기준으로 `checkedInToday`, `skippedToday`, `notCheckedInToday`를 판단한다.
- `MorningCheckInSkipStore`: UserDefaults 기반으로 오늘 하루의 skip 여부만 저장한다. skip은 check-in 기록이 아니며 다음 날 자동 만료된다.
- `MorningCheckInPromptCard`: “오늘 몸 상태를 가볍게 확인해볼까요?”, “10초면 충분해요.” 문구와 `기록하기`, `나중에` CTA를 제공한다.
- Daily Readiness Experience Polish v1에서는 prompt를 더 compact하게 조정하고, “기록하면 오늘 코칭을 조금 더 맞춰볼게요.”처럼 선택적 개인화에 가까운 문구를 사용한다.
- Recovery 화면은 `notCheckedInToday`일 때 prompt를 보여주고, `checkedInToday`일 때 기존 `CheckInSummaryCard`를 보여준다. `skippedToday`일 때는 prompt를 숨겨 사용자를 다시 압박하지 않는다.

v1 보류:

- Push, Widget, Apple Watch 진입점은 구현하지 않는다.
- Check-in은 여전히 score/status/recommendation을 바꾸지 않고 coach message와 insight 개인화에만 사용한다.
