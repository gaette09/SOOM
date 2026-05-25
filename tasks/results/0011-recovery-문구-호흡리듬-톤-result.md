### Summary
`tasks/soom/0011-recovery-문구-호흡리듬-톤.md` 기준으로 dry-run 점검만 수행했습니다. 앱 코드와 문서 파일은 수정하지 않았고, `xcodebuild test/build`도 실행하지 않았습니다.

현재 브랜치: `feature/recovery-ui-density`

프로젝트 구조:
- Xcode 프로젝트: `SOOM.xcodeproj`
- 공유 scheme: `SOOM.xcodeproj/xcshareddata/xcschemes/SOOM.xcscheme`
- 앱 소스: `SOOM/`
- Recovery 관련 코드: `SOOM/Features/Recovery/`
- 테스트 타깃: `SOOMTests/`
- 문서: `docs/`
- 작업 파일: `tasks/soom/`

### Modified Files
없음. dry-run 점검만 수행했습니다.

현재 `git status --short`:
```text
 M automation/telegram/bot.py
?? tasks/results/0010-자동화-명령-연결-상태를-result.md
?? tasks/soom/0010-자동화-명령-연결-상태를.md
?? tasks/soom/0011-recovery-문구-호흡리듬-톤.md
```

### Validation Result
- `xcodebuild test`: 실행하지 않음. 사용자 요청으로 금지됨.
- `xcodebuild build`: 실행하지 않음. 사용자 요청으로 금지됨.
- 실행 가능성 점검 결과:
  - `SOOM.xcodeproj` 존재 확인.
  - `SOOM` 앱 타깃과 `SOOMTests` 테스트 타깃이 scheme에 포함되어 있음.
  - iOS deployment target은 `18.0`, Swift version은 `5.0`으로 설정되어 있음.
  - README 기준 실행 방식은 Xcode에서 `SOOM.xcodeproj`를 열고 iPhone 시뮬레이터로 실행하는 흐름임.

### Risk / Notes
`0011` 작업 파일은 Goal만 있고 `Scope`와 `Files To Check`가 비어 있습니다. 실제 수정 작업으로 전환할 경우 Recovery 문구 대상 파일을 먼저 확정해야 합니다.

관련 후보 영역은 `SOOM/Features/Recovery/`이며, 키워드상 `Recovery`, `호흡`, `리듬` 문구는 Recovery 외에도 Mock/Feed/HealthKit/Activity 문서와 코드에 분산되어 있습니다. 범위 없이 수정하면 작업 범위가 넓어질 위험이 있습니다.

### Suggested Commit Message
`chore: dry-run recovery breathing tone task`