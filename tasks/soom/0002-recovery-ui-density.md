# SOOM Codex Task

## Project
SOOM iOS App

## Goal
Recovery 화면의 정보 우선순위와 카드 간격을 점검하고, 과도하게 넓은 spacing이 있다면 최소 범위에서 개선한다.

## Background
Recovery 화면은 회복 점수, 코치 메시지, 추천 행동, 최신 컨디션 기록, 최근 변화, 인사이트를 보여준다.
최근 구조 개선 후 정보 흐름은 좋아졌지만, 실제 화면에서 카드 간격이나 보조 섹션의 밀도가 과하게 느껴질 수 있다.

## Scope
Recovery 관련 화면과 디자인 토큰만 확인한다.

## Requirements
1. Recovery 화면의 섹션 순서를 유지한다.
2. 회복 점수와 코치 메시지는 핵심 정보로 유지한다.
3. 보조 섹션은 시각적으로 과하게 강조하지 않는다.
4. spacing 조정이 필요하면 최소 변경으로 적용한다.
5. 기능 추가는 하지 않는다.
6. 기존 테스트를 깨뜨리지 않는다.

## Files To Check
- SOOM/Features/Recovery
- SOOM/DesignSystem
- SOOMTests

## Constraints
- main 브랜치에 직접 커밋하지 않는다.
- 기존 기능을 삭제하지 않는다.
- 불필요한 리팩토링은 하지 않는다.
- 작업 범위를 벗어난 파일은 수정하지 않는다.

## Validation
- xcodebuild test 실행 가능하면 실행한다.
- xcodebuild build 실행 가능하면 실행한다.
- 실행하지 못한 경우 이유를 보고한다.

## Result Report
완료 후 아래 형식으로 보고한다.

### Summary
### Modified Files
### Validation Result
### Risk / Notes
### Suggested Commit Message
