# SOOM Shareable Workout Card v1

## A. Purpose

SOOM의 운동 공유는 단순히 기록을 자랑하기 위한 기능이 아니다. 사용자가 자신의 운동 리듬, 꾸준함, 성장 신호를 다른 사람과 자연스럽게 나누고, 다시 운동을 이어갈 동기를 얻는 경험이다.

SOOM의 공유 방향은 과한 경쟁보다 “내 몸과 루틴을 이해하고 조금씩 좋아지는 과정”에 가깝다. Strava처럼 운동 기록의 맥락은 분명히 보여주되, 랭킹이나 자극적인 성취 경쟁보다 Apple Fitness처럼 정돈된 요약과 부드러운 코칭 톤을 유지한다.

공유 카드의 목적:

- 오늘 운동에서 의미 있었던 한 가지를 빠르게 보여준다.
- 기록, 성장, 회복 영향을 하나의 카드로 압축한다.
- 사용자가 공유 여부와 공유 범위를 직접 선택하게 한다.
- 피드에서는 다른 사람의 운동을 비교 대상보다 동기부여 신호로 읽게 한다.
- 장기적으로 Kudos, 응원 댓글, 비슷한 성장 흐름 추천으로 확장한다.

SOOM 공유 톤:

- 성장: “조금씩 좋아지고 있어요.”
- 리듬: “오늘은 리듬을 잘 이어간 운동이에요.”
- 꾸준함: “이번 주 루틴이 안정적으로 이어지고 있어요.”
- 회복: “회복 흐름을 해치지 않는 좋은 강도였어요.”

피해야 할 방향:

- 과한 랭킹, 순위 경쟁, 상대 비교 중심 UX
- 자극적인 achievement tone
- 심박, 위치, 회복 점수를 기본 공개하는 구조
- 사용자가 평가받는 느낌의 피드 문구

## B. Shareable Card Types v1

### Workout Session Summary Card

운동 하나를 공유할 때 가장 기본이 되는 카드다. 운동 타입, 거리/시간, 성장 요약, 다음 힌트, 회복 연결을 짧게 담는다.

사용 상황:

- 운동 상세에서 “오늘 운동 요약”을 공유
- 피드 아이템의 대표 카드
- 이미지 export 또는 iOS share sheet 후보

### Weekly Progress Card

최근 7일 또는 이번 주 운동 흐름을 공유한다. 개인 기록보다 루틴과 꾸준함을 보여주는 카드다.

사용 상황:

- “이번 주 운동 흐름” 공유
- 주간 리포트/회고
- 클럽 또는 동호회에서 가볍게 루틴 공유

### Personal Record Card

PR 또는 의미 있는 개인 성과를 공유한다. 과한 트로피 UX보다 개인 성장 중심으로 표현한다.

사용 상황:

- 최장 거리
- 최고 평균 속도/페이스
- 가장 긴 운동 시간
- 최근 4주 중 의미 있는 성과

### Recovery-Friendly Workout Card

회복 흐름을 해치지 않는 가벼운 운동을 긍정적으로 공유한다. 기록 경신이 아니어도 좋은 운동이었다는 메시지를 만든다.

사용 상황:

- 회복 러닝/라이딩
- 가벼운 조깅
- Z2 세션
- 피로도 높은 날의 안정적 운동

### Consistency Card

운동 빈도와 루틴을 공유한다. SOOM에서는 꾸준함도 성과다.

사용 상황:

- 이번 주 3회 운동
- 4주 연속 기록
- 월간 루틴 유지

### Morning Readiness Card (Future)

Daily Readiness를 바탕으로 오늘의 몸 상태를 공유하는 카드 후보다. v1에서는 구현하지 않고, 향후 사용자가 선택적으로 공유할 수 있는 상태 카드로 둔다.

주의:

- 회복 score는 기본 비공개 후보
- 의료/진단처럼 보이지 않게 표현
- 공유 전 사용자가 노출 정보를 선택해야 함

## C. Card Structure

Shareable Workout Card v1은 하나의 카드 안에서 운동의 규모, 성장 의미, 회복 연결을 짧게 보여준다.

기본 구조 후보:

1. SOOM branding/header
2. 운동 타입
3. 거리/시간 또는 종목별 핵심 지표
4. 성장 요약
5. 회복 영향 또는 다음 힌트
6. 코칭 문장
7. 작은 리듬/성장 메시지
8. SOOM footer

### Required Fields

- `workoutType`
- `distanceText`
- `durationText`
- `sessionSummaryTitle`
- `growthText`
- `recoveryImpactText`
- `coachCopy`
- `sourceLabel` 또는 SOOM footer

### Optional Fields

- pace/speed
- averageHeartRate
- personalRecordText
- weeklyProgressText
- route thumbnail
- club/team context
- privacy label

### Default Hidden Fields

다음 정보는 기본 공유 카드에서 숨기는 것을 우선 검토한다.

- 정확한 위치/경로
- 상세 심박 그래프
- Recovery score
- Check-in note
- 피로도/수면감 같은 주관 컨디션
- HealthKit/Garmin/Samsung 원본 source 상세

## D. Feed Tone

SOOM Feed는 경쟁보다 성장 공유 중심이다. 사용자는 다른 사람의 운동을 보며 “나도 내 리듬을 이어가고 싶다”는 느낌을 받아야 한다.

좋은 Feed 문구:

- “오늘은 리듬을 잘 이어간 운동”
- “조금씩 거리가 길어지고 있어요.”
- “회복 흐름을 해치지 않는 좋은 강도였어요.”
- “이번 주 루틴이 안정적으로 이어지고 있어요.”
- “후반 리듬이 조금 흔들렸지만 전체 흐름은 좋아지고 있어요.”
- “기록보다 꾸준함이 더 좋은 신호였어요.”

피해야 할 Feed 문구:

- “친구보다 빠릅니다.”
- “순위가 떨어졌습니다.”
- “회복 점수가 낮아서 위험합니다.”
- “노력이 부족합니다.”
- “반드시 쉬어야 합니다.”

톤 원칙:

- 상대 비교보다 자기 성장 중심
- 명령보다 제안
- 자극보다 지속 가능성
- 실패보다 다음 힌트
- 숫자보다 의미

## E. Privacy / Sharing Policy

운동 공유는 사용자가 선택적으로 수행해야 한다. SOOM은 건강/운동 데이터를 민감한 개인 데이터로 보고, 기본 공유 정보는 최소화한다.

### Default Sharing Policy

- 사용자가 직접 공유 버튼을 눌렀을 때만 공유
- 위치/경로는 기본 비공개 후보
- 심박, 회복 score, check-in note는 기본 비공개 후보
- 공유 직전 노출 정보를 확인할 수 있어야 함
- 삭제/공개 범위 변경 가능성 필요

### Sharing Scope Candidates

- `private`: 나만 보기
- `followers`: 팔로워 또는 친구 공개
- `public`: 전체 공개

### Sensitive Data Candidates

다음 데이터는 공유 시 명시적 선택이 필요하다.

- 지도 경로
- 정확한 시작/종료 위치
- 심박/파워 상세 데이터
- Recovery score
- Check-in subjective data
- 메모
- HealthKit/Garmin/Samsung source 정보

### Trust Copy Candidates

- “공유 전 노출되는 정보를 확인할 수 있어요.”
- “위치와 회복 점수는 기본으로 공개하지 않아요.”
- “언제든 공유 범위를 바꿀 수 있어야 합니다.”

## F. Feed Future Direction

Shareable Workout Card는 Feed/SNS 기능의 기반이 된다. v1에서는 설계만 진행하고 실제 Feed 구현은 하지 않는다.

Future Feed 후보:

- Kudos
- 응원 댓글
- 저장
- 비슷한 성장 흐름 추천
- 나와 비슷한 라이더/러너
- 클럽 내 주간 루틴 공유
- 같은 코스/비슷한 거리의 성장 흐름 비교

### Feed Item Direction

장기적으로 운동 공유는 `FeedItem`으로 정규화할 수 있다.

후보 타입:

- workoutSessionSummary
- weeklyProgress
- personalRecord
- recoveryFriendlyWorkout
- consistency
- clubActivity

Feed는 “누가 더 잘했는가”보다 “누가 어떤 리듬을 이어가고 있는가”를 보여주는 공간이어야 한다.

## G. Technical Direction

Shareable Workout Card는 기존 Growth/Recovery 해석 레이어를 재사용한다. 새로운 분석 점수나 ML 판단을 만들지 않고, 이미 계산된 interpretation result를 공유 가능한 모델로 정규화한다.

### Model Candidates

#### ShareableWorkoutCardModel

후보 필드:

- `id`
- `cardType`
- `workoutId`
- `workoutType`
- `primaryMetricText`
- `secondaryMetricText`
- `title`
- `summaryText`
- `growthText`
- `recoveryText`
- `coachCopy`
- `privacyLevel`
- `visibleFields`
- `createdAt`

#### ShareableCardType

후보:

- `workoutSessionSummary`
- `weeklyProgress`
- `personalRecord`
- `recoveryFriendlyWorkout`
- `consistency`
- `morningReadiness`

#### SharePrivacyLevel

후보:

- `private`
- `followers`
- `public`

### Data Sources

- `UnifiedWorkout`
- `WorkoutGrowthSummary`
- `WorkoutWeaknessInsight`
- `WorkoutRecoveryImpact`
- `WorkoutSessionSummary`
- `WeeklyWorkoutProgress`
- `PersonalRecord`
- `DailyReadinessState` future

### Export Direction

- iOS Share Sheet
- image export
- in-app Feed item
- club/group post

### Feed Normalization Direction

공유 카드는 장기적으로 FeedItem으로 변환된다. FeedItem은 원본 운동 데이터를 그대로 노출하지 않고, 사용자가 선택한 visible fields만 포함해야 한다.

초기 구현 순서 후보:

1. ShareableWorkoutCardModel 문서화
2. WorkoutSessionSummary → ShareableWorkoutCardModel mapper
3. SwiftUI card preview
4. image export 후보 검토
5. Feed item 모델 설계
6. Kudos/comment MVP

## Implementation Boundaries v1

초기 v1 설계에서는 공유 카드 모델, builder, SwiftUI preview까지를 우선 경계로 두고 다음 항목을 구현하지 않는 것으로 정의했다.

- Feed UI
- SNS API 직접 게시
- image export
- share sheet
- 서버 저장/업로드
- comments/kudos
- 공개 범위 실제 권한 처리
- 위치/심박/Recovery score/Check-in note 같은 민감 정보 선택 포함 옵션

이후 Shareable Growth v1 milestone 안에서 Local Export / Share MVP가 추가되면서 image export와 iOS 기본 Share Sheet는 구현 완료 범위로 이동했다. Feed 저장, 서버 업로드, SNS API 직접 게시, 공개 범위 실제 권한 처리, 위치/심박/Recovery score/Check-in note 같은 민감 정보 선택 포함 옵션은 여전히 미구현/제외 상태다.

v1의 목적은 Growth/Recovery 해석 결과를 공유 가능한 형태로 정리하고, SOOM Feed 제품화 전 안전한 로컬 공유 흐름을 검증하는 것이다.


## MVP Implementation Status

Shareable Workout Card MVP는 설계 문서의 1~3단계를 구현한다. 구현 범위는 `ShareableWorkoutCardModel`, `ShareableWorkoutCardBuilder`, `ShareableWorkoutCardView`, 그리고 Workout Detail 하단의 “공유 카드 미리보기” 섹션이다.

현재 MVP는 다음 경계를 유지한다.

- `WorkoutSessionSummary`, `WorkoutGrowthSummary`, `WorkoutRecoveryImpact`를 재사용해 공유 가능한 문장으로 정리한다.
- 기본 visibility는 `privateOnly`이며, 사용자가 명시적으로 선택하기 전까지 공유되지 않는 전제를 둔다.
- 위치, 심박, Recovery score, Check-in note는 기본 모델에 포함하지 않는다.
- 로컬 image export와 iOS Share Sheet는 아래 Local Export / Share MVP 범위에서 구현한다.
- Feed 저장, 서버 업로드, SNS API 직접 게시, 공개 범위 실제 권한 처리는 future work로 둔다.

## Local Export / Share MVP Status

Shareable Workout Card Export MVP는 공유 카드를 로컬 이미지로 렌더링한 뒤 iOS 기본 Share Sheet로 전달하는 단계다.

구현 범위:

- `ShareableWorkoutCardRenderer`가 `ShareableWorkoutCardView`를 `ImageRenderer` 기반 이미지로 변환한다.
- `WorkoutShareSheet`가 `UIActivityViewController`를 SwiftUI에서 사용할 수 있게 감싼다.
- Workout Detail의 “공유 카드 미리보기” 하단에 “공유하기” 액션을 제공한다.
- 공유 실패 시 부드러운 안내를 표시한다.

유지하는 경계:

- 서버 업로드, Feed 저장, SNS API 연동은 하지 않는다.
- 위치, 심박, Recovery score, Check-in note는 기본 공유 이미지에 포함하지 않는다.
- visibility는 여전히 `privateOnly`가 기본이며, 실제 공개 범위 권한 처리는 future work다.
- 이 기능은 로컬 공유 MVP이며, SOOM Feed 제품화 전 검증 단계로 본다.

## Visual Polish v1 Status

Shareable Workout Card Visual Polish v1은 실제 인스타그램/카카오톡 공유에서 카드가 더 안정적으로 보이도록 export 비율과 카드 내부 위계를 정리한 단계다.

적용 기준:

- 공유 이미지는 4:5 비율을 우선 기준으로 사용한다.
- 기본 export 크기는 360pt x 450pt이며, 3x scale 렌더링으로 1080 x 1350px 공유 이미지를 목표로 한다.
- 카드 상단에는 SOOM branding, 운동 타입 아이콘, “민감 정보 제외” privacy pill을 배치한다.
- 중앙에는 운동의 핵심 메시지를 가장 크게 보여주고, 거리/시간은 보조 metric box로 분리한다.
- 성장 메시지와 회복 메시지는 하나의 muted panel 안에 묶어 공유 카드가 과하게 리포트처럼 보이지 않게 한다.
- footer는 SOOM 출처와 visibility 상태만 조용하게 보여준다.

유지하는 경계:

- Visual polish는 공유 카드의 표현만 다루며, `ShareableWorkoutCardBuilder`의 문구 생성 로직과 Growth/Recovery 해석 로직은 변경하지 않는다.
- 위치, 심박, Recovery score, Check-in note는 계속 기본 공유 이미지에서 제외한다.
- 서버 업로드, Feed 저장, SNS API 연동은 여전히 구현하지 않는다.

## Weekly Progress Share Card MVP Status

Weekly Progress Share Card MVP는 주간 운동 흐름을 공유 가능한 4:5 카드로 정리하는 단계다. 이 카드는 개인 기록 경쟁이 아니라 꾸준함, 성장 리듬, 한 주의 움직임을 부드럽게 보여주는 데 집중한다.

구현 범위:

- `ShareableWeeklyProgressCardModel`이 공유 카드에 필요한 주간 요약 텍스트, 지표, visibility를 보관한다.
- `ShareableWeeklyProgressCardBuilder`가 `WeeklyWorkoutProgress`와 선택적 `FourWeekWorkoutTrend`를 바탕으로 공유 문구를 만든다.
- `ShareableWeeklyProgressCardView`는 기존 공유 카드와 같은 4:5 비율, SOOM branding, privacy cue를 사용한다.
- Analysis 화면의 Weekly Progress 아래에 “공유 카드 미리보기”와 iOS 기본 Share Sheet 액션을 제공한다.

유지하는 경계:

- 서버 업로드, Feed 저장, SNS API 연동은 하지 않는다.
- 위치, 심박, Recovery score, Check-in note, 수면/피로 같은 민감 정보는 기본 포함하지 않는다.
- 비교 문구는 자기 자신의 주간 흐름 기준으로만 작성하며, 랭킹/경쟁/리더보드 톤을 사용하지 않는다.
- 기존 Workout Session Summary 공유 카드 흐름은 그대로 유지한다.
- Weekly Progress Share Card의 기본 visibility는 `privateOnly`이며, View는 모델의 visibility 값을 표시한다.

## Shareable Growth v2 Status

Shareable Growth v2는 v1의 로컬 공유 흐름을 유지하면서 테스트 가능성과 privacy 모델 정합성을 보강하는 단계다.

구현 범위:

- `WorkoutDetailContent`와 `AnalysisView`의 공유 미리보기/민감 정보 안내 문구를 테스트 가능한 상수로 정리한다.
- 공유 버튼에서 사용하는 이미지 렌더링 흐름을 주입 가능한 closure로 열어, 화면 흐름 테스트에서 renderer 호출을 확인할 수 있게 한다.
- `ShareableWeeklyProgressCardModel`에 visibility를 추가해 Workout Session Summary Card와 같은 privacy 정책 구조로 맞춘다.
- 세션 카드와 주간 카드에서 반복되던 privacy pill UI를 `ShareablePrivacyBadge`로 공통화한다.
- `WorkoutShareSheet`는 `UIActivityViewController` 생성 흐름을 테스트할 수 있도록 작은 factory method를 제공한다.

유지하는 제외 범위:

- 서버 업로드
- Feed 저장
- SNS API 직접 게시
- 공개 범위 실제 권한 처리
- 위치/심박/Recovery score/Check-in note/수면/피로 같은 민감 정보 선택 포함 옵션

공유 히스토리 저장 준비:

- 향후 서버 또는 로컬 공유 히스토리를 도입할 때는 원본 운동 데이터를 저장하지 않고, 카드 타입, workout id 또는 weekly range, visibility, 생성 시각, export format, 사용자가 확인한 visible fields만 별도 기록한다.
- 공유 히스토리 저장은 명시적 사용자 액션 이후에만 발생해야 하며, v2에서는 실제 저장을 구현하지 않는다.

TODO:

- 공개 범위 UI가 생기면 `ShareableWorkoutVisibility`를 Workout/Weekly 공통 정책으로 유지하면서 실제 권한 처리 계층을 별도로 추가한다.
