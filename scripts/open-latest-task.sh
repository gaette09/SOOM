#!/bin/bash

LATEST_FILE=$(find tasks/soom -name "*.md" ! -name "TEMPLATE.md" | sort | tail -1)

if [ -z "$LATEST_FILE" ]; then
  echo "No task file found."
  exit 1
fi

echo "Opening:"
echo "$LATEST_FILE"

open "$LATEST_FILE"
