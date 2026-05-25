#!/bin/bash

TASK_NAME=$1
DATE=$(date +%Y-%m-%d)
TASK_ID=$(printf "%04d" $(( $(ls tasks/soom | grep -E '^[0-9]+' | wc -l) + 1 )))

FILE="tasks/soom/${TASK_ID}-${TASK_NAME}.md"

cp tasks/soom/TEMPLATE.md "$FILE"

echo "Created:"
echo "$FILE"
