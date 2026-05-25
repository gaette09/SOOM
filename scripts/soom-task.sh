#!/bin/bash

TASK_NAME=$1

if [ -z "$TASK_NAME" ]; then
  echo "Usage: ./scripts/soom-task.sh task-name"
  exit 1
fi

TASK_ID=$(printf "%04d" $(( $(find tasks/soom -name "*.md" ! -name "TEMPLATE.md" | wc -l) + 1 )))
FILE="tasks/soom/${TASK_ID}-${TASK_NAME}.md"

cp tasks/soom/TEMPLATE.md "$FILE"

echo "Created:"
echo "$FILE"
echo ""

open "$FILE"

echo "Codex prompt:"
echo "tasks/soom/$(basename "$FILE") 파일을 기준으로 작업해줘. 작업 전 현재 git status를 확인하고, main 브랜치에 직접 커밋하지 말고 필요한 경우 feature 브랜치를 만들어 진행해줘. 완료 후 Result Report 형식으로 보고해줘."
