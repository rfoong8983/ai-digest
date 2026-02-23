#!/bin/bash
export LANG=en_US.UTF-8

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

exec >> "$PROJECT_DIR/digest.log" 2>&1
echo "=== $(date) ==="
cd "$PROJECT_DIR"
bundle exec ruby bin/digest
echo "Exit code: $?"
