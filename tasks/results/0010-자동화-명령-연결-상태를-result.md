### Summary
[tasks/soom/0010-자동화-명령-연결-상태를.md](/Volumes/Platinum1TB/SOOM/tasks/soom/0010-자동화-명령-연결-상태를.md)를 기준으로 dry-run 점검만 수행했습니다. 앱 코드와 문서 파일은 수정하지 않았고, `xcodebuild test/build`도 실행하지 않았습니다.

현재 브랜치: `feature/recovery-ui-density`

자동화 연결 경로는 다음 구조로 확인됩니다:  
`automation/telegram/bot.py` → `./scripts/soom-task.sh` → `./scripts/run-latest-task.sh --dry|normal` → `codex exec`

### Modified Files
제가 수정한 파일은 없습니다.

현재 git 상태:
```text
## feature/recovery-ui-density
 M automation/telegram/bot.py
?? tasks/soom/0010-자동화-명령-연결-상태를.md
```

### Validation Result
- 프로젝트 구조 확인: `SOOM.xcodeproj`, `SOOM/`, `SOOMTests/`, `scripts/`, `tasks/`, `automation/telegram/` 존재 확인.
- 스크립트 실행 권한 확인: `scripts/*.sh`는 실행 가능 상태입니다.
- Bash 문법 확인: `scripts/run-latest-task.sh`, `scripts/soom-task.sh` 등 통과.
- Python AST 파싱 확인: `automation/telegram/*.py` 통과.
- 의존 명령 확인: `codex`, `python3`, `bash`, `open`, `git` 확인됨.
- Python 패키지 확인: `requests`, `dotenv` import 가능. 단, `urllib3`의 LibreSSL 관련 경고가 표시됩니다.
- `.env` 확인: `automation/telegram/.env` 존재하며 `.gitignore`에 포함되어 있습니다.
- `xcodebuild test/build`: 사용자 지시로 실행하지 않음.

### Risk / Notes
- `automation/telegram/bot.py`는 현재 수정된 상태이며, `/soom`, `/soomdry` 명령 연결 코드가 포함되어 있습니다.
- `run_soom_task()`에서 Telegram 입력값 `goal`을 shell 문자열에 직접 넣고 있어, 따옴표 등 특수 문자가 포함되면 실행 안정성 문제가 생길 수 있습니다.
- 실제 Telegram API 호출, `codex exec`, task 생성 실행은 수행하지 않았습니다.

### Suggested Commit Message
커밋 없음. Dry-run 점검만 수행했습니다.