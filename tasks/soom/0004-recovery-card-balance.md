# SOOM Codex Task

## Project
SOOM iOS App

## Goal
Recovery 화면에서 핵심 카드와 보조 카드의 시각적 위계를 점검하고, 핵심 정보가 더 먼저 읽히도록 최소 범위에서 정리한다.

## Background
Recovery 화면은 회복 점수, 코치 메시지, 추천 행동, 최신 컨디션 기록, 최근 변화, 인사이트를 포함한다.
이전 작업에서 보조 섹션 spacing은 일부 줄였지만, 카드별 강조 수준이 균형 있게 보이는지 추가 점검이 필요하다.

## Scope
Recovery 화면의 카드 구성, spacing, 시각적 강조 수준만 확인한다.

## Requirements
1. 회복 점수와 코치 메시지는 가장 중요한 정보로 유지한다.
2. 추천 행동은 사용자가 바로 실행할 수 있는 보조 핵심 정보로 유지한다.
3. 최근 변화와 인사이트는 과하게 강조하지 않는다.
4. 기능 추가는 하지 않는다.
5. 계산 로직은 수정하지 않는다.
6. 필요 시 Recovery 관련 spacing 또는 카드 스타일만 최소 수정한다.
7. 기존 테스트를 깨뜨리지 않는다.

## Files To Check
- SOOM/Features/Recovery
- SOOM/Components
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
