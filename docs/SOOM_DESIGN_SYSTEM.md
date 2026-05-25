# SOOM Design System

SOOM은 Native iOS, SwiftUI 기반의 건강/운동 데이터 앱이다. 디자인 시스템의 목적은 운동 데이터를 차분하고 신뢰감 있게 보여주면서, 사용자가 자신의 몸 상태와 다음 행동을 쉽게 이해하도록 돕는 것이다.

## Product Direction

- Apple Fitness의 정돈된 감성, 넓은 호흡, iOS다운 부드러운 전환
- Strava의 운동 데이터 중심 UX, 지도 경로, 스플릿, 피드 기반 활동 맥락
- 초보자도 이해할 수 있는 운동 요약, 회복 판단, 위험 신호
- 장기적으로 회복, 피로도, 운동 습관, AI 코칭까지 확장 가능한 구조
- 과도하게 귀엽거나 게임스럽지 않은 차분한 브랜드 톤

## Design Principles

### 1. Data First, Calm Always

운동 기록, 컨디션, 회복, 위험 신호가 먼저 보인다. 장식은 정보 이해를 돕는 수준으로만 사용한다.

좋은 예:
- "최근 30일 러닝 볼륨 +29%, 부상 위험 상승"처럼 데이터와 판단을 함께 보여준다.
- 지도, 거리, 시간, 심박, 페이스가 상세 화면의 중심이 된다.

나쁜 예:
- 감성 문구, 배지, 소셜 반응이 운동 데이터보다 먼저 보인다.
- 색상과 애니메이션이 많아 데이터가 묻힌다.

### 2. Beginner-Friendly, Athlete-Ready

초보자는 한 문장 요약으로 이해하고, 숙련자는 그래프와 지표로 깊게 확인할 수 있어야 한다.

좋은 예:
- "오늘은 회복 러닝이 적합합니다"와 함께 근거 지표를 제공한다.
- 상세 화면에서 요약, 그래프, 스플릿, 존 정보를 순차적으로 탐색할 수 있다.

나쁜 예:
- 지표만 나열하고 의미를 설명하지 않는다.
- AI 코칭이 구체적인 다음 행동 없이 응원 문구로 끝난다.

### 3. Native iOS Motion

SwiftUI, MapKit, Charts, NavigationStack, ScrollView의 기본 감각을 존중한다. 화면 전환, 시트 드래그, 내부 스크롤은 예측 가능해야 한다.

좋은 예:
- 상세 시트는 중앙, 확장, 축소 상태가 분명하다.
- 상단 고정 상태에서만 내부 스크롤이 가능하다.

나쁜 예:
- 같은 드래그가 어떤 때는 시트를 움직이고 어떤 때는 내부 스크롤을 움직인다.
- Safe Area와 상태바 배경이 분리되어 보인다.

## Color System

SOOM의 색상은 직접 `Color(hex:)`를 화면에서 쓰지 않고 `SOOMColor` 토큰을 통해 사용한다.

### Appearance Policy

SOOM v1은 브랜드 일관성과 초기 UI 완성도를 위해 Light Mode only 정책을 사용한다. Dark Mode는 디자인 시스템 안정화 이후 v2에서 지원한다.

코드에서 `.preferredColorScheme(.light)`를 유지하는 경우, 이 정책을 설명하는 주석을 남긴다. v2에서 Dark Mode를 지원할 때는 색상 토큰의 의미를 유지한 상태로 배경, 표면, 라인, 텍스트 대비를 먼저 재정의한다.

### Brand Colors

- Blue: `#0047AB`
- Orange: `#FF8F00`
- Green: `#16302B`
- Red: `#B80F0A`
- Black: `#161616`
- White: `#FCFCF0`

### Semantic Usage

- `SOOMColor.background`: 앱 기본 배경
- `SOOMColor.surface`: 카드/시트 표면
- `SOOMColor.ink`: 주요 텍스트
- `SOOMColor.secondaryInk`: 보조 텍스트
- `SOOMColor.line`: 카드 경계, 구분선
- `SOOMColor.swim`: 수영
- `SOOMColor.bike`: 사이클
- `SOOMColor.run`: 러닝
- `SOOMColor.warning`: 피로, 경고, 고강도
- `SOOMColor.recovery`: 회복, 저강도, 안정 신호

### Color Rules

- 색상은 의미를 가져야 한다.
- 운동 종목 색상과 상태 색상을 혼동하지 않는다.
- 위험, 피로, 회복은 색상만으로 표현하지 않고 반드시 텍스트/수치와 함께 표시한다.
- 새 색상이 필요하면 문서와 `SOOMColor`에 먼저 정의한다.

## Typography

SOOM은 큰 제목과 중요한 수치에는 Gmarket Sans, 본문과 설명에는 NanumSquare Neo를 사용한다.

### Usage

- `SOOMFont.display`: 화면 제목, 핵심 메시지, 큰 수치
- `SOOMFont.displayMedium`: 섹션 제목, 내비게이션 제목
- `SOOMFont.body`: 본문, 캡션, 보조 설명, 지표 라벨

### Typography Rules

- 큰 글자는 진짜 중요한 정보에만 사용한다.
- 카드 내부 제목은 과도하게 키우지 않는다.
- Dynamic Type에서 텍스트가 겹치거나 잘리지 않아야 한다.
- 단위는 일관되게 표기한다. 예: `151 bpm`, `5:02/km`, `10.4 km`

## Spacing

기본 화면 좌우 여백은 `20pt`, 카드 간격은 `16pt`를 기준으로 한다. 주요 간격은 `SOOMLayout`에서 관리한다.

### Rules

- 화면마다 임의의 padding 값을 만들지 않는다.
- 상세 시트, 지도 컨트롤, 하단 탭바처럼 복잡한 레이아웃은 별도 토큰 그룹을 만든다.
- 하단 탭바와 상세 시트는 Safe Area와 홈 인디케이터 영역을 반드시 고려한다.

## Radius

기본 카드 반경은 `8pt`다. 반경은 `SOOMRadius` 또는 `SOOMLayout` 토큰을 사용한다.

### Rules

- 일반 카드는 8pt를 유지한다.
- 큰 유리형 탭바, 지도 상세 시트처럼 동작 자체가 형태를 만드는 요소만 별도 반경을 사용한다.
- 카드 안에 또 다른 장식 카드가 들어가는 중첩 구조는 피한다.

## Components

### Core Components

- `SOOMScreen`: 화면 기본 배경, 스크롤, 하단 오버레이 인셋
- `SOOMCard`: 반복 카드 컨테이너
- `SOOMSectionHeader`: 섹션 제목/설명
- `SOOMMetricPill`: 작은 지표 카드
- `SOOMMetricRing`: 점수형 상태 지표
- `SOOMMetricRow`: 스플릿, 존, 세부 기록처럼 반복되는 지표 행
- `SOOMActionRow`: 목록형 액션 행
- `SOOMIconButton`: 접근성 라벨을 포함한 아이콘 버튼
- `FlowTags`: 태그/관심사/클럽 속성 표시
- `RecoveryScoreCard`: 회복 점수, 상태, 추천 행동을 한 번에 보여주는 핵심 상태 카드
- `DailyReadinessCard`: Recovery score를 새로 계산하지 않고 오늘의 준비 상태를 짧게 해석하는 요약 카드
- `InsightCard`: 짧은 분석 인사이트와 근거를 보여주는 카드
- `RecommendationCard`: 오늘 할 수 있는 구체적인 행동 제안 카드
- `TrendCard`: 휴식기 심박, 운동 부하, 수면, 피로도 같은 변화 추세 카드
- `RecoveryTimelineCard`: 최근 며칠의 회복 상태 흐름을 시간 축으로 보여주는 보조 카드
- `WeeklyCoachSummaryCard`: 저장된 일별 회복 스냅샷을 바탕으로 한 주 흐름을 가볍게 요약하는 코칭 카드
- `CoachMessageCard`: AI 코치의 판단을 차분한 코칭 메시지로 보여주는 카드
- `RecoveryExplanationCard`: 현재 회복 상태가 왜 나왔는지 짧고 이해 가능한 이유를 보여주는 카드

### Component Rules

- 같은 UI가 두 번 이상 반복되면 컴포넌트 후보로 본다.
- 컴포넌트는 색상, 폰트, 반경, 간격 토큰을 사용한다.
- 화면별 특수 로직이 컴포넌트 내부로 과하게 들어가지 않도록 한다.
- Metric 컴포넌트는 표시 형태별로 파일을 분리한다. `Pill`, `Ring`, `Row`, `ActionRow`는 서로 다른 책임으로 본다.
- `Components` 폴더는 특정 Feature의 데이터 흐름을 알지 않는 순수 UI 패턴만 가진다.
- Preview는 컴포넌트의 기본 상태를 빠르게 확인할 수 있도록 간단한 더미 텍스트와 색상만 사용한다.

### Recovery / AI Coach Card Patterns

Recovery와 AI Coach 컴포넌트는 복잡한 생체/운동 데이터를 사용자가 바로 이해할 수 있는 상태, 이유, 다음 행동으로 압축한다.

- `RecoveryScoreCard`: 화면 상단에서 회복 상태의 대표 점수와 추천 행동을 요약한다. 점수만 강조하지 않고 상태 라벨과 오늘의 행동을 함께 표시한다.
- `DailyReadinessCard`: Recovery score/status를 기반으로 “오늘 준비 상태”를 한 문장으로 먼저 보여준다. 별도 점수나 차트를 만들지 않고, RecoveryScoreCard를 대체하지 않는 가벼운 interpretation layer로 사용한다.
- `InsightCard`: 최근 변화나 위험 신호를 한 문장으로 설명한다. `neutral`, `positive`, `warning` 톤을 사용하되 색상만으로 의미를 전달하지 않는다.
- `RecommendationCard`: "오늘 무엇을 하면 좋은가"를 명확히 제안한다. 실제 네비게이션/기록 시작 액션은 외부에서 closure로 주입한다.
- `TrendCard`: 현재값, 단위, 변화 문구, 방향을 함께 표시한다. 초기 버전에서는 복잡한 차트 대신 미니 라인과 텍스트만 사용한다.
- `RecoveryTimelineCard`: 최근 3~5일의 회복 점수, 상태, 짧은 이유를 세로 흐름으로 보여준다. 복잡한 라인 차트가 아니라 “오늘 상태가 어떤 흐름에서 이어졌는가”를 이해시키는 보조 정보로 사용한다. Timeline은 저장된 `DailyRecoverySnapshot`을 읽는 historical layer이며, Recovery 화면 진입 후 오늘 snapshot이 저장되면서 점진적으로 채워진다. snapshot이 없을 때는 fake history 대신 부드러운 empty state를 보여준다.
- `WeeklyCoachSummaryCard`: 최근 7일 `DailyRecoverySnapshot`을 읽어 평균 회복 점수, 주간 흐름, 코치 인사이트, 다음 주 추천을 요약한다. 점수 계산 카드가 아니라 장기 흐름을 해석하는 보조 카드이며, 리포트처럼 무겁지 않게 1개 카드로 압축한다.
- `CoachMessageCard`: 챗봇 대화 UI가 아니라 건강/운동 코칭 카드로 표현한다. 메시지는 짧고 실행 가능한 방향이어야 한다.
- `RecoveryExplanationCard`: 회복 점수와 코치 메시지 사이의 이유를 설명한다. 수치 계산을 자세히 노출하기보다 “최근 부하가 높음”, “휴식 리듬이 안정적임”, “체감 피로가 높음”처럼 사용자가 바로 이해할 수 있는 말로 표현한다.

### Feature Folder Rules

- `Activity`: 운동 기록, 운동 상세, 분석, 기록 시작 흐름
- `Feed`: 커뮤니티 피드, 피드 상세, 소셜 반응
- `Profile`: 클럽, 사용자/그룹 성격의 정보
- `Recovery`: 회복, 피로도, 부상 위험, 회복 추천

Feed/Community 성격의 화면은 Activity에서 분리한다. 단, 운동 상세 내부의 공유 카드처럼 Activity 데이터와 강하게 결합된 작은 UI는 해당 Feature 안에 둘 수 있다.

## Feature UI Guidance

### Home

홈은 사용자의 현재 상태를 3초 안에 알려야 한다. 컨디션, 최근 30일 변화, AI 코칭, 최근 운동이 중심이다.

### Activity

운동 상세는 지도, 요약, 그래프, 스플릿, 존, AI 해석 순서로 자연스럽게 읽혀야 한다.

Workout/Growth 화면은 SOOM의 “성장 동기부여 축”이다. Recovery가 오늘의 몸 상태와 회복 판단을 담당한다면, Workout Detail은 특정 운동이 사용자의 기록, 리듬, 페이스, 심박 안정성, 주간 흐름에서 어떤 의미를 갖는지 설명한다.

Workout Growth 기준:

- Strava처럼 기록성과 PR, 이전 운동 대비 개선을 분명하게 보여준다.
- Apple Fitness처럼 요약, 성과, 부족한 점, 코칭 인사이트를 정돈된 순서로 배치한다.
- SOOM의 코칭 톤으로 부족한 점을 실패가 아니라 다음 운동 힌트로 표현한다.
- 성장 신호는 기록 경신뿐 아니라 꾸준함, 심박 안정성, 저강도 지속 시간, 운동 빈도까지 포함한다.
- 운동 상세의 회복 연결은 Recovery score를 대체하지 않고, “이 운동이 회복에 남긴 영향”을 보조적으로 설명한다.
- `WorkoutGrowthCard`는 운동 요약 바로 아래에 두는 성장 동기부여 layer다. 한 번에 하나의 성장 신호만 보여주며, 과한 배지나 게임식 보상보다 차분한 비교 문장과 다음 운동 힌트를 우선한다.
- `WorkoutWeaknessCard`는 correction이 아니라 coaching layer다. Growth 카드 아래에서 “다음에 좋아질 수 있는 점”을 하나만 제안하며, 부정적 평가나 강한 경고 색을 피한다.
- `WeeklyWorkoutProgressCard`는 성장 동기부여용 주간 요약 카드다. Analysis 화면에서 최근 7일 운동 횟수, 총 거리, 총 시간을 압축해 보여주며, Recovery 판단이 아니라 Workout/Growth 축의 흐름 이해를 돕는다.
- `FourWeekWorkoutTrendCard`는 장기 동기부여용 보조 카드다. Analysis 화면에서 `WeeklyWorkoutProgressCard` 아래에 배치해 최근 4주 거리/시간/횟수 흐름을 차분하게 보여준다. 복잡한 차트 대신 미니 바와 짧은 코칭 문장으로 “리듬이 어떻게 이어지는지”를 설명한다.
- `PersonalRecordCard`는 경쟁보다 개인 성장 중심의 achievement 카드다. PR을 과한 배지/트로피처럼 보상화하지 않고, 거리/시간/페이스 같은 성과를 차분한 비교 문장과 동기부여 문장으로 정리한다.

상세 기준 문서는 [SOOM_WORKOUT_GROWTH_EXPERIENCE.md](SOOM_WORKOUT_GROWTH_EXPERIENCE.md)를 따른다.

### Recovery

회복 기능은 위험을 과장하지 않고, 피로도와 휴식 필요성을 차분하게 설명해야 한다.

Recovery 화면은 MVP 단계에서 다음 순서를 기본 패턴으로 사용한다.

1. 화면 제목과 짧은 설명
2. `DailyReadinessCard`로 오늘 준비 상태를 짧게 요약
3. `RecoveryScoreCard`로 오늘의 회복 상태 요약
4. `CoachMessageCard`로 AI 코치의 한 문장 판단
5. `RecoveryExplanationCard`로 왜 이런 회복 상태인지 설명
6. `RecommendationCard`로 바로 실행 가능한 행동 제안
7. 최신 check-in이 있으면 `CheckInSummaryCard`로 오늘 컨디션 기록 요약
8. `TrendCard`로 휴식기 심박, 운동 부하, 피로도 추세 표시
9. `RecoveryTimelineCard`로 최근 회복 흐름을 보조적으로 표시
10. `WeeklyCoachSummaryCard`로 저장된 일별 스냅샷 기반의 주간 흐름을 요약
11. `InsightCard`로 사용자가 이해해야 할 짧은 해석 제공
12. Check-in 기록/히스토리 진입은 화면 하단의 보조 액션으로 둔다.

Recovery 화면은 “오늘 핵심”을 먼저 보여준다. 사용자가 3초 안에 몸 상태, 코치 판단, 추천 행동을 이해해야 하며, Trends, Timeline, Insights는 판단 근거를 확인하고 싶은 사용자를 위한 보조 정보로 둔다.

- 핵심 카드: 회복 점수, 코치 메시지, 설명, 추천 행동
- 보조 카드: 최신 check-in, 최근 변화, 회복 흐름, 주간 요약, 인사이트
- 관리 액션: 컨디션 기록하기, 기록 보기
- HealthKit 연결 UI: Recovery 핵심 카드가 아니라 화면 하단의 설정/관리 액션에 둔다. 권한 요청 화면은 상태 확인과 read-only 정책 설명에 집중하며, 회복 점수 카드처럼 보이게 만들지 않는다.
- HealthKit workout preview: 연결 확인용 보조 화면으로만 사용한다. 최근 운동 목록은 타입, 날짜, 시간, 거리, 심박, 칼로리 정도만 보여주고, Recovery 핵심 카드나 운동 상세 화면처럼 무겁게 만들지 않는다.
- HealthKit workout import UI: 관리/연결 영역의 수동 실행 화면이다. import 버튼과 마지막 결과 요약만 제공하고, Recovery 핵심 화면과 분리한다. 사용자가 가져온 기록이 아직 회복 점수에 자동 반영되지 않는다는 점을 명확히 안내한다.
- Unified Workout Library: 가져온 workout을 검토하는 데이터 관리 화면이다. 운동 타입, source, 날짜, 거리, 시간, dataQuality, 분석 제외 상태를 목록으로 보여주되, Recovery 핵심 UI나 Workout Detail처럼 코칭/분석 화면으로 보이게 만들지 않는다.
- Analysis Exclusion: “분석 제외”는 삭제/경고/destructive action처럼 표현하지 않는다. 사용자가 Recovery/Growth 계산 후보에서 잠시 빼는 관리 상태이므로 secondary tone, subtle badge, “기록은 유지된다”는 안내를 함께 사용한다. 제외 상태는 언제든 “분석 포함”으로 되돌릴 수 있어야 한다.
- Unified Workout Duplicate Review: Library에서 들어가는 데이터 검토 화면이다. 중복 후보, confidence, 판단 근거, 우선 source를 보여주지만 삭제/병합 버튼은 제공하지 않는다. 이 화면은 사용자가 데이터를 이해하는 관리 영역이며, 운동 성과나 회복 코칭처럼 감정적 보상을 주는 화면이 아니다.
- HealthKit Recovery preview: 관리/검증 영역에서만 제공하는 개발용 화면이다. HealthKit source 기반 score/status/recommendation을 보여줄 수 있지만, 핵심 Recovery 화면과 명확히 분리하고 “개발용 미리보기”임을 표시한다.
- Trends와 Insights가 길어질 경우에는 즉시 접힘 UI를 추가하기보다 먼저 카드 개수와 문장 길이를 조정한다. 접힘 구조는 정보량이 실제로 늘어났을 때 도입한다.

#### Recovery UI Polish v1

- `RecoveryScoreCard`는 첫 화면의 중심 카드로 유지하고, 그 아래 코치 메시지/설명/추천은 같은 핵심 묶음 안에서 차분하게 이어지게 한다.
- 최신 check-in, Trends, Timeline, Insights는 보조 해석 영역으로 묶어 상단 핵심 카드보다 시각적으로 가볍게 다룬다.
- Trend와 Insight 카드는 큰 숫자와 문장 밀도를 낮춰 스크롤 피로감을 줄인다. 정보는 유지하되, 보조 정보가 핵심 상태를 압도하지 않게 한다.
- Check-in CTA는 기록 행동을 유도하되 핵심 카드처럼 무겁게 보이지 않도록 `SOOMActionRow` 중심의 가벼운 카드 패턴을 사용한다.
- 섹션 간격은 핵심 영역에는 충분한 호흡을, 보조 영역에는 묶음감을 주는 방향으로 `SOOMLayout.RecoveryScreen` 토큰을 사용한다.

#### Recovery UI Polish v2

- 핵심 영역은 `오늘 핵심`으로 묶고, 사용자가 첫 화면에서 오늘 상태, 이유, 다음 행동을 순서대로 이해하게 한다.
- 보조 영역은 check-in 요약, 최근 변화, Timeline, Weekly Summary, Insights처럼 흐름/기록/해석을 확인하는 구간으로 둔다. 섹션 caption은 짧게 유지해 카드보다 설명 문구가 무겁게 보이지 않게 한다.
- Timeline은 일별 흐름, Weekly Summary는 7일 요약으로 역할을 분리한다. 두 카드가 같은 리포트처럼 느껴지지 않도록 caption에서 범위를 명확히 한다.
- 관리 영역은 컨디션 기록, 기록 보기, HealthKit 연결을 하나의 compact action card 안에 묶는다. 기록 액션은 보조 행동이며, 핵심 회복 판단 카드보다 낮은 시각적 우선순위를 가진다.
- HealthKit 연결은 Recovery 핵심 경험이 아니라 데이터 연결 관리 영역이다. read-only 권한 확인과 preview 진입은 화면 하단에서 차분하게 제공한다.

#### Daily Readiness MVP

- Daily Readiness는 Recovery의 “오늘 상태 요약 layer”다. `RecoverySummary.score/status`를 읽어 ready, moderate, recovery, insufficient data 중 하나로 해석한다.
- 별도 점수, gauge, prediction을 만들지 않는다. Recovery score/status/recommendation은 그대로 유지하고, 사용자가 첫눈에 오늘 접근 방식을 이해하도록 돕는다.
- `DailyReadinessCard`는 `RecoveryScoreCard` 바로 위에 배치하되, 더 큰 수치 카드처럼 경쟁하지 않게 짧은 제목과 메시지만 사용한다.

#### Daily Readiness Experience Polish v1

- `DailyReadinessCard`는 상단 핵심 상태를 담당하고, `MorningCheckInPromptCard`는 그 상태를 더 개인화하기 위한 보조 prompt로만 사용한다.
- Morning Prompt는 큰 CTA 카드처럼 보이지 않게 compact한 아이콘, 짧은 문장, 낮은 대비의 버튼을 사용한다. 기록하지 않아도 괜찮다는 선택감을 유지한다.
- “오늘 준비 상태 → 회복 점수 → 이유 → 오늘 추천 행동” 흐름이 끊기지 않도록 핵심 영역 caption은 행동까지 이어지는 문장으로 둔다.
- 하단 관리 영역의 check-in 액션은 prompt와 경쟁하지 않게 “새로 기록하기” 수준의 secondary action으로 표현한다.
- 명령형/진단형 문장을 피하고, “맞춰볼게요”, “필요할 때”처럼 부드러운 코칭 톤을 사용한다.

#### Morning Check-in Flow v1

- Morning Check-in은 Daily Readiness를 보조하는 lightweight prompt다. 사용자가 아침에 SOOM을 열고 오늘 상태를 확인한 뒤, 10초 안에 컨디션을 남길 수 있게 돕는다.
- Prompt는 핵심 Recovery 판단보다 가볍게 보여야 한다. “오늘 몸 상태를 가볍게 확인해볼까요?”처럼 부드러운 문장을 사용하고, 기록하지 않아도 괜찮다는 선택감을 유지한다.
- Morning Check-in은 `CheckInSummaryCard`, coach message, insight 개인화로 이어지는 피드백 루프를 만든다. 단, Recovery score/status/recommendation을 직접 바꾸지 않는다.
- `MorningCheckInPromptCard`는 오늘 기록이 없을 때만 표시한다. 오늘 기록이 있으면 prompt 대신 `CheckInSummaryCard`로 기록 결과를 확인하게 한다.
- Home, Recovery, Push, Widget, Apple Watch는 모두 후보 entry point지만, v1의 기준 화면은 Recovery다.

실제 HealthKit 연동 전까지는 mock 데이터를 사용하되, View는 데이터 출처를 알지 않는 구조를 유지한다.

HealthKit 연결 전에는 `docs/SOOM_RECOVERY_DATA_CONTRACT.md`와 화면 모델을 먼저 정의한다. UI는 `RecoveryViewModel`이 제공하는 요약 모델만 읽고, 권한 요청이나 원천 데이터 수집 방식에 직접 의존하지 않는다.

### Profile

프로필/클럽/커뮤니티는 운동 데이터 중심 경험을 보조해야 한다. 소셜 지표가 건강 판단보다 강하게 보이면 안 된다.

## Review Checklist

- 새 화면이 SOOM의 운동 데이터 중심 방향과 맞는가?
- 원시 색상, 원시 폰트, 임의 간격이 직접 사용되지 않았는가?
- 카드, 섹션, 지표, 버튼 패턴이 기존 컴포넌트와 일관되는가?
- 상태바, Safe Area, 하단 탭바, 상세 시트가 자연스럽게 이어지는가?
- 그래프/지도/아이콘에 접근성 정보가 있는가?
- 장기적으로 회복, 피로도, AI 코칭을 붙여도 구조가 무너지지 않는가?

## Analysis Architecture Cleanup v1

Analysis 화면은 점진적으로 Container/ViewModel 구조로 이동한다. View는 카드 배치와 화면 위계만 담당하고, SwiftData store 생성, provider 조립, loading/error/fallback 상태는 Container와 ViewModel에서 관리한다. 이 정책은 Recovery 화면의 container 패턴과 같은 방향으로 유지한다.

## Workout Recovery Impact Card

`WorkoutRecoveryImpactCard`는 Workout Detail의 coaching layer다. Growth Card가 좋아진 점, Weakness Card가 다음에 좋아질 수 있는 점을 말한다면, Recovery Impact Card는 “이 운동 이후 회복 리듬을 어떻게 바라볼지”를 짧게 연결한다.

디자인 기준:

- 위치는 `WorkoutGrowthCard`와 `WorkoutWeaknessCard` 아래가 기본이다.
- 경고 카드처럼 강하게 보이지 않게 subtle tint와 짧은 문장을 사용한다.
- “위험”, “나쁨”, “무리”처럼 불안감을 주는 표현보다 “조금 더 챙기기”, “확인하기”, “가볍게 마무리” 같은 코칭 톤을 쓴다.
- Recovery score를 대체하거나 재계산하는 카드처럼 보이면 안 된다.

## Workout Session Summary Card

Workout Session Summary Card는 운동 상세의 핵심 해석 카드다. 운동 기본 수치 아래, Growth/Weakness/Recovery Impact 카드 위에 배치해 사용자가 오늘 운동 결과를 먼저 이해하게 한다.

- 시각적 역할: 상세 화면의 “오늘 운동 요약”으로 가장 먼저 읽히는 해석 카드
- 내용 구조: 요약 제목, 짧은 설명, 좋아진 점, 다음 힌트, 회복 연결, 마무리 동기부여
- 디자인 톤: Strava의 기록성은 유지하되 Apple Fitness처럼 차분하고 정돈된 카드 밀도를 사용한다.
- 제한: 과한 배지, 복잡한 차트, 부정적인 평가 문구는 사용하지 않는다.

## Feed / Shareable Workout Card Tone

SOOM의 Feed/SNS 경험은 경쟁보다 성장 공유 중심이다. 공유 카드는 사용자가 자신의 운동 리듬, 꾸준함, 회복 친화적 선택을 차분하게 보여주는 도구이며, 랭킹이나 자극적인 achievement tone이 핵심이 아니다.

- 좋은 공유 카드: 오늘 운동 요약, 성장 신호, 다음 힌트, 회복 연결을 짧게 보여준다.
- 피해야 할 공유 카드: 상대 비교, 과한 배지, 순위 압박, 위치/심박/회복 score 기본 공개.
- 공유 문구는 “리듬을 이어갔어요”, “조금씩 좋아지고 있어요”, “회복 흐름을 해치지 않는 좋은 강도였어요”처럼 부드럽고 자기 성장 중심이어야 한다.
- Feed UI는 Workout/Growth 데이터를 기반으로 하되 사용자가 선택한 정보만 노출한다. 위치, 심박, Recovery score, Check-in note는 기본 비공개 후보로 둔다.

공유 카드 제품/기술 방향은 [SOOM_SHAREABLE_WORKOUT_CARD.md](SOOM_SHAREABLE_WORKOUT_CARD.md)를 따른다.



## Shareable Workout Card MVP

`ShareableWorkoutCardView`는 성장 공유 preview 카드다. 실제 Feed/SNS 기능이 아니라, 운동 상세에서 사용자가 어떤 내용이 공유 카드로 보일지 확인하는 단계다.

디자인 기준:

- SOOM branding, 운동 타입, 거리/시간, 성장 메시지, 회복 연결, footer만 간결하게 보여준다.
- 위치, 심박, Recovery score, Check-in note는 기본 노출하지 않는다.
- `privateOnly` visibility를 기본값으로 사용해 개인정보 보호 우선 원칙을 유지한다.
- 카드 톤은 Instagram식 공유 가능성은 갖되, 랭킹/트로피/경쟁보다 Apple Fitness처럼 정돈된 성장 기록에 가깝게 유지한다.
- Workout Detail에서는 하단 preview 영역에 배치해 세션 해석 흐름을 방해하지 않는다.

### Local Share / Export

- 공유 액션은 v1에서 iOS 기본 Share Sheet를 사용한다. 별도 SNS API나 서버 업로드를 붙이지 않는다.
- 공유 이미지는 `ShareableWorkoutCardView`의 preview 내용만 렌더링한다. 위치, 심박, Recovery score, Check-in note는 기본 포함하지 않는다.
- “공유하기”는 Workout Detail 하단의 preview 보조 액션으로 둔다. 운동 해석 흐름보다 시각적으로 무겁게 보이면 안 된다.
- 공유 실패 문구는 오류를 크게 강조하지 않고 “공유 카드 이미지를 만들 수 없어요”처럼 부드럽게 안내한다.


### Shareable Card Visual Polish v1

- 공유 카드는 4:5 비율을 기본 export 기준으로 사용한다. 인스타그램 피드와 카카오톡 이미지 공유에서 잘리지 않는 안정적인 비율을 우선한다.
- 시각 위계는 branding/privacy → 핵심 메시지 → 거리/시간 → 성장/회복 메시지 → footer 순서로 읽히게 한다.
- 핵심 메시지는 카드의 중심 정보이며, 거리/시간은 작은 metric box로 보조한다. 공유 카드가 운동 상세 화면처럼 모든 데이터를 담으려 하면 안 된다.
- 성장/회복 메시지는 muted panel에 묶어 차분한 코칭 느낌을 유지한다. 과한 배지, 트로피, 랭킹 장식은 사용하지 않는다.
- 기본 export는 3x scale을 사용해 retina 공유 이미지 품질을 유지한다.
- “민감 정보 제외” 표시는 신뢰를 주는 subtle privacy cue이며, 경고나 보안 배너처럼 무겁게 보이면 안 된다.

## Weekly Progress Share Card

Weekly Progress 공유 카드는 “꾸준함/성장 공유” 중심의 보조 공유 카드다. Workout Session 공유 카드가 단일 운동의 해석을 보여준다면, Weekly Progress 공유 카드는 한 주 동안의 운동 횟수, 총 거리, 총 시간을 차분하게 정리한다.

디자인 기준:

- 기존 공유 카드와 같은 4:5 비율과 SOOM branding을 사용해 export 품질을 일관되게 유지한다.
- 핵심 메시지는 “이번 주 리듬”, “꾸준함”, “조금씩 이어간 성장”처럼 자기 성장 중심으로 작성한다.
- 위치, 심박, Recovery score, Check-in note, 수면/피로 정보는 기본 노출하지 않는다.
- 랭킹, 상대 비교, 리더보드, 과한 achievement 장식은 사용하지 않는다.
- Analysis 화면에서는 Weekly Progress Card 아래에 배치해 분석 흐름을 방해하지 않는 preview/action 영역으로 유지한다.

## Recovery Real Data Preview

Recovery Real Data Preview는 검증/관리 영역이며 핵심 Recovery UI와 분리한다. 사용자는 HealthKit import로 저장된 실제 운동 기록이 Recovery 계산 흐름에서 어떻게 해석되는지 미리 볼 수 있지만, 이 결과가 기본 Recovery 점수에 자동 반영된다고 느끼면 안 된다.

Visual 기준:

- preview score는 공식 Recovery score보다 낮은 시각 우선순위를 가진다.
- `Recovery Score`처럼 공식 점수로 읽히는 라벨보다 `미리보기 점수`, `검증용 Recovery 흐름`처럼 boundary가 드러나는 표현을 우선한다.
- imported workout 기준, 분석 제외 workout 미반영, DeduplicationEngine 자동 미적용 상태를 낮은 우선순위 안내로 제공한다.
- 안내 문구는 개발자 도구처럼 딱딱하지 않게, “회복 흐름을 미리 확인”하는 제품 언어로 유지한다.

디자인 기준:

- HealthKit 설정/관리 화면의 보조 entry로 둔다.
- “가져온 운동 기록만 기준”, “아직 기본 Recovery 점수에는 자동 반영되지 않음”을 명확히 안내한다.
- score/status/recommendation은 보여주되, 핵심 Recovery 화면보다 낮은 시각적 우선순위를 유지한다.
- 빈 데이터와 오류 상태는 불안감을 주지 않는 부드러운 문장으로 안내한다.


## Recovery Comparison Preview

Recovery Comparison은 `공식 Recovery > Preview Recovery > 차이 설명` 순서의 위계를 따른다.

- 공식 Recovery score는 기준점으로 가장 명확하게 표시한다.
- Preview score는 검증용 값으로 보조 위계에 둔다.
- 비교 문구는 차이를 설명하되, 공식 점수가 틀렸다는 인상을 주지 않는다.
- 차이 설명은 imported workout 범위, 분석 제외 설정, 중복 기록 가능성처럼 사용자가 확인할 수 있는 항목에 집중한다.

### Local Feed Mock MVP

SOOM Feed의 첫 구현은 서버 없는 local mock 기반이다. 피드는 `ShareableWorkoutCardView`와 `ShareableWeeklyProgressCardView`를 재사용해 운동 세션과 주간 성장 흐름을 보여주며, 좋아요/댓글/팔로우 기능 없이 성장 공유 톤을 검증한다.

디자인 기준:
- Feed item은 작성자, 시간, caption, 공유 카드 preview 순서로 구성한다.
- 카드의 시각적 무게는 운동 데이터보다 “리듬과 성장 메시지”가 먼저 읽히도록 둔다.
- 공개 범위 badge는 subtle하게 표시하고, 민감 정보 제외 원칙을 공유 카드와 동일하게 유지한다.
- Feed는 Instagram식 경쟁/성과 과시보다 Apple Fitness에 가까운 차분한 성장 기록 모음처럼 보여야 한다.
- Ranking, leaderboard, 승패 표현, 자극적인 achievement tone은 사용하지 않는다.



## Motion System v1

SOOM motion is defined in `SOOM_MOTION_SYSTEM_V1.md` and tokenized lightly in `SOOMMotion`. Motion should support the rhythm of workout data without distracting from reading. Feed, Share, Recovery, and Analysis surfaces should use restrained ease-out motion, subtle press feedback, and no heavy social bounce.

Design 기준:

- Primary motion is reserved for important state changes such as share card reveal, recovery summary updates, or sheet position changes.
- Secondary motion supports button/card feedback and should remain quick and subtle.
- Background motion should be rare, slow, and removable when Reduce Motion is enabled.
- Feed card motion should use fade plus slight upward movement rather than bounce.
- Recovery score and readiness motion should feel stable and trustworthy.
- Share card export motion should keep the rendered card visually stable.
- Tap scale should not go below `0.98` for cards and primary actions.


### Feed Motion Polish v1

Feed card motion is the first application of the SOOM Motion System. The local Feed uses restrained reveal motion and subtle press feedback only.

- Feed items appear with fade plus a small upward offset.
- Stagger is minimal and should never delay reading.
- Reduce Motion disables the movement and keeps content readable.
- Press feedback uses `SOOMMotion.Scale.pressed` and should not feel like a social reaction.
- Visibility badges in Feed remain preview/trust cues, not full permission enforcement.


### HealthKit Manual Import CTA

HealthKit import is a management feature, but during the early real-data validation phase it must remain easy to find. The primary CTA should use direct wording such as `HealthKit 운동 가져오기` rather than only `연결` when the user can actually start a manual import flow.

Design 기준:

- Place the manual import CTA near the top of the HealthKit settings surface, below connection status.
- Copy must make the boundary clear: imported workouts can support Growth analysis and Recovery preview, but they do not automatically replace the official Recovery score.
- Do not make the CTA look like automatic background sync.
- Keep HealthKit import in the management/connection area, not as a core Recovery score card.

### HealthKit Import Placement

HealthKit import is a data connection task. The primary CTA should live in Record > Data Connection with direct copy such as `Apple 건강 앱 운동 가져오기`. Recovery may keep a lower-priority management link, but the core Recovery cards should not imply that imported data is already the official score source.

The CTA copy must keep the boundary clear: imported workouts can support Growth analysis and Recovery preview, while official Recovery still uses its existing provider until an explicit rollout.

### Liquid Glass Tab Bar v1

The bottom tab bar should behave as a compact floating navigation surface above content. It uses a lighter material, smaller selected pill, softer shadow, and reduced vertical height while keeping comfortable tap targets. The center Record tab can stay visually useful, but it should not become a heavy action button.

## Workout Growth Metrics Card

`WorkoutGrowthMetricsCard`는 운동 상세의 상세 분석 카드다. Session Summary가 오늘 운동을 한 문단으로 요약한다면, Growth Metrics Card는 거리, 시간, 페이스/속도, 고도, 심박 효율 같은 세부 지표를 3~5개 row로 정리한다.

디자인 톤은 판단보다 흐름 설명을 우선한다. `improved`, `steady`, `lighter`, `insufficientData` 상태는 강한 평가나 경고가 아니라 리듬 변화의 신호로 표현한다. 카드 위치는 `WorkoutSessionSummaryCard` 아래, `WorkoutGrowthCard` 위를 기본으로 하며 복잡한 차트 없이 value와 짧은 비교 문장 중심으로 유지한다.

Workout detail metrics는 sport-specific hierarchy를 따른다. 러닝/걷기는 페이스 중심, 라이딩은 평균 속도와 상승 고도 중심, 수영은 100m 페이스 중심으로 보여준다. 서로 다른 종목의 기록을 한 baseline으로 섞지 않으며, 같은 종목 기록이 부족하면 다른 종목으로 보정하지 않고 부드러운 insufficient state를 보여준다.

## Workout Map Detail Direction

Workout detail map은 운동 상세의 상단 핵심 visual layer다. Mapbox interactive map은 route shape와 이동 리듬을 보여주고, floating overlay는 거리, 시간, pace/speed, elevation처럼 가장 중요한 2~4개 지표만 담는다.

Design 기준:

- 지도는 운동 기록의 맥락을 보여주되 숫자 카드보다 과하게 무겁지 않아야 한다.
- Summary/feed card는 static route preview 또는 sport-specific fallback을 사용한다.
- Detail page는 interactive map + 아래 metric sections 구조를 따른다.
- Zone cards는 하단 보조 분석으로 두고, 라이딩은 heart rate/cadence/power zone 확장을 우선 고려한다.
- Route/location data는 민감 정보로 취급하며 share/feed에서는 기본 비공개다.

### Static Route Preview Card v1

Static route preview는 공유/피드 카드의 supporting visual layer다. 지도나 경로가 운동 기록의 분위기를 도와줄 수는 있지만, 거리/시간/성장 메시지보다 높은 시각 우선순위를 가져서는 안 된다.

Design 기준:

- 카드 상단에 작고 차분하게 배치한다.
- route preview는 metrics와 coaching copy를 보조하는 배경/맥락 역할이다.
- token이나 route가 없으면 sport-specific fallback을 보여주고, 오류처럼 보이게 하지 않는다.
- 위치 데이터는 민감 정보이므로 route preview는 privacy-first layer로 취급한다. share/feed preview는 기본적으로 시작/종료 지점 masking을 적용하고, caller가 명시적으로 route preview를 넘긴 경우에만 표시한다.
- Actual Static Map Image Loading v1은 `AsyncImage`로 static route image를 표시할 수 있다. 이미지는 낮은 대비 supporting layer로 유지하고, share/feed static preview는 Workout Detail interactive map과 분리한다.


Actual static route image를 표시할 때는 metrics/message hierarchy를 넘지 않도록 opacity overlay와 작은 높이를 유지한다. Loading과 failure는 오류처럼 보이지 않게 sport fallback으로 조용히 처리한다.

Route privacy masking은 오류나 경고처럼 보이지 않게 조용히 적용한다. masking으로 인해 route preview가 부족하면 sport fallback을 보여주고, metrics와 coaching copy 흐름은 유지한다.

세부 설계는 [SOOM_WORKOUT_MAP_DETAIL_EXPERIENCE.md](SOOM_WORKOUT_MAP_DETAIL_EXPERIENCE.md)를 따른다.

### Workout Zone Cards

Zone card는 correction이나 diagnosis가 아니라 coaching layer다. Heart rate, cadence, power zone은 사용자의 운동 리듬을 이해시키는 보조 정보로 표시하며, 강한 warning color나 “해야 한다”는 명령형 표현을 피한다.

Zone Cards v1은 `WorkoutZoneCard`와 `WorkoutZoneSection`을 통해 Workout Detail의 Growth Metrics 아래에 배치되며, dashboard 과밀화 없이 dominant zone과 간단한 distribution bar를 보여준다.

Design 기준:

- Dominant zone과 duration/percentage를 짧게 보여준다.
- 데이터가 없을 때는 unavailable을 부드럽게 표현하고, card 전체를 error처럼 보이게 하지 않는다.
- Power zone은 FTP가 없으면 숨기거나 unavailable로 둔다.
- Zone insight는 “오늘은 Zone 2 유지 시간이 길었어요”처럼 흐름을 설명하는 문장으로 유지한다.
- Recovery score나 Growth score처럼 보이지 않게 보조 분석 위계에 둔다.
- Data source badge는 trust cue다. `HealthKit 데이터`, `기본 추정`, `데이터 없음`처럼 작고 낮은 우선순위로 표시하며, warning/error UI처럼 보이게 하지 않는다.

## Workout Detail Map Overlay

Workout Detail의 map overlay는 운동 상세의 첫 hero layer다. 지도는 운동 흐름을 빠르게 인식시키는 supporting visual이며, floating metric overlay가 거리/시간/종목별 핵심 지표를 먼저 읽히게 한다.

- 지도는 카드보다 넓은 hero surface로 배치하되 Growth/Recovery cards보다 과하게 튀지 않게 한다.
- Floating metrics는 2~4개로 제한하고 running은 pace, cycling은 speed/elevation, swimming은 route fallback과 100m pace 중심으로 둔다.
- token 없음, route 없음, map load 실패에서는 sport-specific fallback을 사용한다.
- 복잡한 route animation이나 replay는 SOOM v1의 차분한 데이터 리듬과 맞지 않으므로 보류한다.

## Settings / My Page Foundation

Settings/My Page는 단순한 부가 화면이 아니라 데이터 신뢰를 관리하는 핵심 관리 영역이다. 프로필, 데이터 연결, 운동 기준값, 공개 범위, 알림, 앱 정보를 한곳에서 확인하되, Recovery나 Growth 핵심 화면보다 낮은 시각 우선순위를 유지한다.

Design 기준:

- Profile summary는 로그인 전에도 placeholder로 안정적으로 보여준다.
- HealthKit import/connection은 Settings에서도 접근 가능해야 하며, 공식 Recovery 자동 반영처럼 보이면 안 된다.
- FTP, 최대 심박 같은 training baseline은 Workout Detail Zone Cards의 개인화 기준값으로 설명하되, Recovery/Growth 핵심 계산에는 적용되지 않는다고 명확히 말한다.
- 공개 범위 설정은 privacy-first 기본값을 유지하고 위치, 심박, 체크인 메모가 자동 공유되지 않는다는 신뢰 문구를 포함한다.

### Personalized Zone Baseline

Personalized zone은 training dashboard가 아니라 trust/personalization layer다. `최대심박 기준`, `FTP 기준` 같은 작은 badge로 사용자가 zone 계산 기준을 이해하게 하되, 경고나 의료적 판단처럼 보이면 안 된다.

- Badge는 zone bar보다 낮은 시각 우선순위를 가진다.
- FTP/maxHR 기준은 Workout Detail Zone Cards에만 적용하며 Recovery/Growth 핵심 계산과 섞지 않는다.
- 기준값이 없으면 기존 fallback/unavailable copy를 유지한다.


### Route Comparison Insight Card

Comparison cards are “previous me” coaching cards, not ranking or judgement cards. They should sit after Growth Metrics and before Zone Analysis so the flow reads as: what happened today, what changed compared with my recent similar effort, then how the intensity was distributed.

Design 기준:

- Use calm metric rows, not leaderboard or trophy language.
- `insufficientData` should feel like a gentle future promise: “비슷한 기록이 쌓이면 비교해볼게요.”
- Route similarity is a trust cue, not a precision claim. Avoid implying exact segment matching in v1.
- Negative evaluation words such as failure/poor performance should not appear.
- RecoveryCalculator and Growth score policy are not visually or conceptually mixed into this card.

## Split Insight Layer

Split Insight is a pacing/rhythm interpretation layer in Workout Detail. It should read as a calm coaching cue about “후반 흐름” or “리듬 유지,” not as a competitive segment result or performance judgment. Place it after comparison and before zone analysis so the user moves from previous-me comparison into today’s internal workout rhythm.

## Workout Detail Information Hierarchy v1

Workout Detail은 기능 카드를 단순 나열하지 않고 네 개의 읽기 그룹으로 묶는다. 목표는 사용자가 “오늘 운동의 핵심”을 먼저 이해하고, 이후 성장 흐름, 센서 데이터, 회복 해석을 차분히 내려 읽게 하는 것이다.

- `오늘 핵심`: map hero 다음에 기본 metrics와 session summary를 배치한다.
- `성장 흐름`: Growth Metrics, Growth Summary, Comparison Insight, Split Insight를 한 흐름으로 둔다.
- `운동 데이터`: Zone Analysis, chart, split table처럼 근거 데이터를 확인하는 supporting layer다.
- `회복 해석`: Recovery Impact, Weakness/Coaching, AI interpretation, next action을 마지막 해석 layer로 둔다.

Section header는 divider나 강한 card shell이 아니라 작은 title/caption으로 처리한다. Motion은 fade와 아주 작은 upward reveal 정도만 허용하고, Reduce Motion에서는 정보 전달이 animation에 의존하지 않아야 한다.

## Course Record Card

Course Record is a personal growth cue, not a competitive achievement badge. The card should say “비슷한 코스에서 이전 나와 비교” and avoid leaderboard, ranking, or loud trophy language.

Design 기준:

- Place it inside the Workout Detail `성장 흐름` group after Comparison Insight and before Split Insight.
- Use one primary metric and one previous-baseline row rather than a dense table.
- Improvement copy should be subtle: “조금 더 가벼운 리듬”, “이전보다 빠른 흐름”.
- `insufficientData` should feel like a future promise, not an error.
- Recovery score, Growth score, and social ranking should not be visually mixed into this card.


## Course Identity and Same-route Records

Course identity is a supporting interpretation layer, not a competitive ranking system. Same-route records should be framed as “이전 나와의 코스 흐름” and use cautious copy such as “비슷한 코스” when the app relies on heuristic route matching. Reverse-direction matches are allowed when the route signals are close enough, but UI should avoid claiming exact segment identity until a stronger map-matching layer exists.

## Course Progression Card

Course Progression is a long-term growth flow card. It should help the user understand “how this course has been changing for me over time” without feeling like a leaderboard or race result.

Design 기준:

- Place it in Workout Detail `성장 흐름` after Course Record and before Split Insight.
- Show a short summary plus the latest 3-5 timeline rows; avoid dense charts.
- Use calm direction cues: improving, stable, fluctuating, insufficient data.
- Keep copy centered on “이전 나와의 흐름” and avoid hard claims when route matching is heuristic.
- Recovery score, Growth score, Feed ranking, and social comparison should not be mixed into this card.

## Climb Insight Card

Climb Insight is a terrain/rhythm interpretation card. It should appear in Workout Detail after Split Insight and before Zone Analysis when elevation data is meaningful, especially for cycling and hiking.

Design 기준:

- Use calm copy such as “오르막 리듬”, “지형에 맞춘 조절”, and “완만한 지형 변화”.
- Avoid segment leaderboard, trophy, or harsh fatigue language.
- Show only a few rows: elevation gain, average grade, and optional late-climb rhythm.
- Hide flat or low-confidence routes rather than forcing an empty dashboard.
- Keep Recovery score, Feed ranking, and complex climb charts out of this card.

## Terrain Context Layer

Terrain is an 운동 맥락 layer. It should explain the shape of the workout route before the user reads growth, split, climb, zone, and recovery cards. The visual treatment should stay smaller than primary metrics and avoid badge-heavy or competitive language.

Design 기준:

- Place the cue near the map hero as supporting context.
- Use calm labels such as “평지 중심”, “롤링 지형”, “꾸준한 오르막”, and “트레일/하이킹”.
- Treat mixed and urban stop-go labels as route context, not diagnostic or performance labels.
- Difficulty labels are soft context only: 가벼운 난이도, 중간 난이도, 도전적인 흐름.
- Avoid diagnostic or performance-judgement copy.
- Keep Recovery score, Feed ranking, and complex terrain charts out of this cue.

## Progression Intelligence Card

Progression Intelligence is a 장기 흐름 해석 card. It belongs in Analysis or Home-level progression sections, not Workout Detail, because it summarizes repeated workouts over time rather than one workout session.

Design 기준:

- Use calm labels such as “최근 흐름”, “안정적으로 이어지는 흐름”, and “다시 리듬을 쌓는 흐름”.
- Keep rows simple: primary pace/speed, workout frequency, and rhythm stability.
- Avoid complex charts, prediction language, ranking, or weekly AI coach tone.
- Treat fluctuating or rebuilding as neutral rhythm context, not failure.
- Keep Recovery score and Feed/social comparison out of this card.

## Auth / My Page Foundation

My Page and Auth are part of SOOM's data trust foundation. v1 should make local ownership clear before adding server accounts, and it should explain whether the user is in local-only mode or a future signed-in state.

Design 기준:

- Show local-only status as a calm trust cue, not a warning.
- Keep future Apple, Google, and Supabase login affordances disabled or clearly marked as 준비 중 until implemented.
- Profile identity, HealthKit management, privacy defaults, and training baselines belong together because they shape user-owned data.
- Do not imply cloud sync or account backup before server/Auth is actually connected.
