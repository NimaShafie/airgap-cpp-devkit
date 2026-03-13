#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: This script must be run inside a Git repository."
  exit 1
fi
cp "$REPO_ROOT/tools/coding-standard/.clang-format" "$REPO_ROOT/.clang-format"
echo "OK: Synced root .clang-format from tools/coding-standard/.clang-format"
