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

### Recovery

회복 기능은 위험을 과장하지 않고, 피로도와 휴식 필요성을 차분하게 설명해야 한다.

Recovery 화면은 MVP 단계에서 다음 순서를 기본 패턴으로 사용한다.

1. 화면 제목과 짧은 설명
2. `RecoveryScoreCard`로 오늘의 회복 상태 요약
3. `CoachMessageCard`로 AI 코치의 한 문장 판단
4. `RecoveryExplanationCard`로 왜 이런 회복 상태인지 설명
5. `RecommendationCard`로 바로 실행 가능한 행동 제안
6. 최신 check-in이 있으면 `CheckInSummaryCard`로 오늘 컨디션 기록 요약
7. `TrendCard`로 휴식기 심박, 운동 부하, 피로도 추세 표시
8. `RecoveryTimelineCard`로 최근 회복 흐름을 보조적으로 표시
9. `WeeklyCoachSummaryCard`로 저장된 일별 스냅샷 기반의 주간 흐름을 요약
10. `InsightCard`로 사용자가 이해해야 할 짧은 해석 제공
11. Check-in 기록/히스토리 진입은 화면 하단의 보조 액션으로 둔다.

Recovery 화면은 “오늘 핵심”을 먼저 보여준다. 사용자가 3초 안에 몸 상태, 코치 판단, 추천 행동을 이해해야 하며, Trends, Timeline, Insights는 판단 근거를 확인하고 싶은 사용자를 위한 보조 정보로 둔다.

- 핵심 카드: 회복 점수, 코치 메시지, 설명, 추천 행동
- 보조 카드: 최신 check-in, 최근 변화, 회복 흐름, 주간 요약, 인사이트
- 관리 액션: 컨디션 기록하기, 기록 보기
- HealthKit 연결 UI: Recovery 핵심 카드가 아니라 화면 하단의 설정/관리 액션에 둔다. 권한 요청 화면은 상태 확인과 read-only 정책 설명에 집중하며, 회복 점수 카드처럼 보이게 만들지 않는다.
- HealthKit workout preview: 연결 확인용 보조 화면으로만 사용한다. 최근 운동 목록은 타입, 날짜, 시간, 거리, 심박, 칼로리 정도만 보여주고, Recovery 핵심 카드나 운동 상세 화면처럼 무겁게 만들지 않는다.
- HealthKit Recovery preview: 관리/검증 영역에서만 제공하는 개발용 화면이다. HealthKit source 기반 score/status/recommendation을 보여줄 수 있지만, 핵심 Recovery 화면과 명확히 분리하고 “개발용 미리보기”임을 표시한다.
- Trends와 Insights가 길어질 경우에는 즉시 접힘 UI를 추가하기보다 먼저 카드 개수와 문장 길이를 조정한다. 접힘 구조는 정보량이 실제로 늘어났을 때 도입한다.

#### Recovery UI Polish v1

- `RecoveryScoreCard`는 첫 화면의 중심 카드로 유지하고, 그 아래 코치 메시지/설명/추천은 같은 핵심 묶음 안에서 차분하게 이어지게 한다.
- 최신 check-in, Trends, Timeline, Insights는 보조 해석 영역으로 묶어 상단 핵심 카드보다 시각적으로 가볍게 다룬다.
- Trend와 Insight 카드는 큰 숫자와 문장 밀도를 낮춰 스크롤 피로감을 줄인다. 정보는 유지하되, 보조 정보가 핵심 상태를 압도하지 않게 한다.
- Check-in CTA는 기록 행동을 유도하되 핵심 카드처럼 무겁게 보이지 않도록 `SOOMActionRow` 중심의 가벼운 카드 패턴을 사용한다.
- 섹션 간격은 핵심 영역에는 충분한 호흡을, 보조 영역에는 묶음감을 주는 방향으로 `SOOMLayout.RecoveryScreen` 토큰을 사용한다.

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
