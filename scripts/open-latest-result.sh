#!/bin/bash

LATEST_RESULT=$(find tasks/results -name "*.md" | sort | tail -1)

if [ -z "$LATEST_RESULT" ]; then
  echo "No result file found."
  exit 1
fi

echo "Opening:"
echo "$LATEST_RESULT"

open "$LATEST_RESULT"
