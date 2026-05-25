#!/bin/bash

LATEST_FILE=$(find tasks/soom -name "*.md" ! -name "TEMPLATE.md" | sort | tail -1)

if [ -z "$LATEST_FILE" ]; then
  echo "No task file found."
  exit 1
fi

PROMPT="$LATEST_FILE 파일을 기준으로 작업해줘. 작업 전 현재 git status를 확인하고, main 브랜치에 직접 커밋하지 말고 필요한 경우 feature 브랜치를 만들어 진행해줘. 완료 후 Result Report 형식으로 보고해줘."

echo "Running Codex with:"
echo "$LATEST_FILE"
echo ""

codex "$PROMPT"
