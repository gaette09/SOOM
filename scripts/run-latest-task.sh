#!/bin/bash

MODE=$1

LATEST_FILE=$(find tasks/soom -name "*.md" ! -name "TEMPLATE.md" | sort | tail -1)

if [ -z "$LATEST_FILE" ]; then
  echo "No task file found."
  exit 1
fi

TASK_BASE=$(basename "$LATEST_FILE" .md)
RESULT_FILE="tasks/results/${TASK_BASE}-result.md"

if [ "$MODE" = "--dry" ]; then
  PROMPT="$LATEST_FILE 파일을 기준으로 dry-run 점검만 해줘. 실제 앱 코드와 문서 파일은 수정하지 말고, 현재 git status, 프로젝트 구조, 실행 가능성만 확인한 뒤 Result Report 형식으로 보고해줘. xcodebuild test/build는 실행하지 마."
else
  PROMPT="$LATEST_FILE 파일을 기준으로 작업해줘. 작업 전 현재 git status를 확인하고, main 브랜치에 직접 커밋하지 말고 필요한 경우 feature 브랜치를 만들어 진행해줘. 완료 후 Result Report 형식으로 보고해줘."
fi

echo "Running Codex Exec:"
echo "$LATEST_FILE"
echo ""

echo "Mode:"
if [ "$MODE" = "--dry" ]; then
  echo "dry-run"
else
  echo "normal"
fi
echo ""

echo "Result will be saved to:"
echo "$RESULT_FILE"
echo ""

codex exec \
  --sandbox workspace-write \
  -o "$RESULT_FILE" \
  "$PROMPT"

echo ""
echo "Completed."
echo "Saved:"
echo "$RESULT_FILE"
