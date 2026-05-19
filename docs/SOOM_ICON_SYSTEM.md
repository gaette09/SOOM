# SOOM Icon System

SOOM은 SwiftUI `Image(systemName:)`와 SF Symbols를 기본 아이콘 시스템으로 사용한다. 아이콘의 역할은 장식이 아니라 운동 데이터와 행동을 빠르게 인식시키는 것이다.

## Principles

### 1. Functional, Not Decorative

아이콘은 사용자가 기능, 종목, 상태를 빠르게 이해하도록 돕는다. 의미 없는 장식 아이콘은 사용하지 않는다.

### 2. Consistent Across Screens

같은 개념은 항상 같은 아이콘을 사용한다. 홈, 상세, 피드, 클럽에서 러닝/사이클/수영 아이콘이 바뀌면 안 된다.

### 3. Calm and Native

SF Symbols의 iOS다운 선명함을 유지한다. 과도한 커스텀 아이콘, 복잡한 그림체, 게임 배지처럼 보이는 스타일은 피한다.

### 4. Accessible by Default

터치 가능한 모든 아이콘 버튼은 `accessibilityLabel`을 가져야 한다. 의미가 불분명한 경우 `accessibilityHint`도 제공한다.

## Core Icons

아이콘 이름은 `SOOMIcon`에서 관리한다. 화면 내부에서 문자열을 직접 반복하지 않는다.

| Meaning | SF Symbol |
| --- | --- |
| 홈 | `house.fill` |
| 분석 | `chart.xyaxis.line` |
| 기록 | `plus.circle.fill` |
| 피드 | `person.2.fill` |
| 클럽 | `flag.checkered` |
| 수영 | `figure.pool.swim` |
| 사이클 | `bicycle` |
| 러닝 | `figure.run` |
| 브릭 | `point.3.connected.trianglepath.dotted` |
| 뒤로가기 | `chevron.left` |
| 접기 | `chevron.down` |
| 저장 | `bookmark` |
| 더보기 | `ellipsis` |

## Icon Categories

### Navigation Icons

탭바와 화면 이동에 사용하는 아이콘이다. 탭바 아이콘은 항상 라벨과 함께 제공한다.

좋은 예:
- 아이콘 + 텍스트 `홈`, `분석`, `기록`, `피드`, `클럽`

나쁜 예:
- 아이콘만 있는 탭바
- 같은 탭이 화면마다 다른 아이콘을 사용하는 경우

### Sport Icons

운동 종목을 나타내는 아이콘이다.

- 수영: `figure.pool.swim`
- 사이클: `bicycle`
- 러닝: `figure.run`
- 브릭: `point.3.connected.trianglepath.dotted`

운동 종목 아이콘은 종목 색상과 함께 사용한다. 단, 색상만으로 종목을 구분하지 않는다.

### Action Icons

저장, 더보기, 닫기, 접기 등 사용자 행동을 나타낸다. 액션 아이콘은 터치 영역이 충분해야 하며 접근성 라벨을 가진다.

좋은 예:

```swift
Button {
    // action
} label: {
    Image(systemName: SOOMIcon.bookmark)
}
.accessibilityLabel("경로 저장")
```

나쁜 예:

```swift
Image(systemName: "bookmark")
```

## Size System

아이콘 크기는 컴포넌트별 `SOOMLayout` 토큰을 따른다.

- 탭바 기본 아이콘: `26pt`
- 기록 탭 아이콘: `28pt`
- 지도 컨트롤 아이콘: `21-22pt`
- 상세 헤더 종목 아이콘: `15pt`
- 일반 액션 버튼 아이콘: `20pt`

## Touch Target

- 터치 가능한 아이콘은 최소 `44pt x 44pt` 영역을 확보한다.
- 지도 위 컨트롤은 시각적으로 원형 버튼이며 충분한 그림자와 배경 대비를 가진다.
- 작은 아이콘을 단독으로 터치 대상에 두지 않는다.

## Color

아이콘 색상은 `SOOMColor`를 사용한다.

- 기본 액션: `SOOMColor.ink`
- 수영: `SOOMColor.swim`
- 사이클: `SOOMColor.bike`
- 러닝: `SOOMColor.run`
- 경고/피로: `SOOMColor.warning`
- 회복/안정: `SOOMColor.recovery`

## Accessibility Rules

### Required

- 아이콘 버튼에는 `accessibilityLabel`을 제공한다.
- 상태나 수치를 의미하는 아이콘은 텍스트/수치와 함께 읽히게 한다.
- 그래프, 지도, 경로 아이콘은 대체 설명을 제공한다.

### Good Labels

- `뒤로가기`
- `상세 정보 접기`
- `경로 저장`
- `더보기`
- `러닝 상세`

### Bad Labels

- `button`
- `bookmark`
- `ellipsis`
- 비어 있는 라벨

## Review Checklist

- 새 아이콘이 `SOOMIcon`에 등록되어 있는가?
- 같은 의미의 아이콘이 화면마다 동일한가?
- 터치 가능한 아이콘에 접근성 라벨이 있는가?
- 아이콘이 장식이 아니라 기능/상태/종목 이해를 돕는가?
- 아이콘 크기와 터치 영역이 `SOOMLayout` 토큰을 따르는가?
- 과도하게 귀엽거나 게임스러운 스타일로 흐르지 않는가?
