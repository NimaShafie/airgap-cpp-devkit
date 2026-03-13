#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: This script must be run inside a Git repository."
  exit 1
fi
cd "$REPO_ROOT"
echo "core.hooksPath:"
git config --local --get core.hooksPath || true
echo
[ -f "$REPO_ROOT/.clang-format" ] && echo "OK: found .clang-format" || echo "ERROR: missing .clang-format"
[ -f "$REPO_ROOT/tools/coding-standard/.clang-tidy" ] && echo "OK: found .clang-tidy" || echo "ERROR: missing .clang-tidy"
command -v clang-format >/dev/null 2>&1 && clang-format --version || echo "ERROR: clang-format missing"
command -v clang-tidy >/dev/null 2>&1 && clang-tidy --version || echo "WARNING: clang-tidy missing"
if command -v python3 >/dev/null 2>&1; then python3 --version; elif command -v python >/dev/null 2>&1; then python --version; else echo "ERROR: Python missing"; fi
