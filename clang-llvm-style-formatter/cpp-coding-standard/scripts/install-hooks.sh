#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: This script must be run inside a Git repository."
  exit 1
fi
cd "$REPO_ROOT"

echo "=================================================="
echo "C++ Coding Standard Setup"
echo "Repo: $REPO_ROOT"
echo "=================================================="
echo

echo "[1/6] Configuring repo-local Git hooks path..."
git config --local core.hooksPath tools/coding-standard/hooks
echo "OK: core.hooksPath = $(git config --local --get core.hooksPath)"
echo

echo "[2/6] Checking required files..."
[ -f "$REPO_ROOT/.clang-format" ] || { echo "ERROR: Missing repo root .clang-format"; exit 1; }
echo "OK: Found .clang-format"
[ -f "$REPO_ROOT/tools/coding-standard/.clang-tidy" ] || { echo "ERROR: Missing tools/coding-standard/.clang-tidy"; exit 1; }
echo "OK: Found tools/coding-standard/.clang-tidy"
[ -f "$REPO_ROOT/tools/coding-standard/hooks/pre-commit" ] || { echo "ERROR: Missing tools/coding-standard/hooks/pre-commit"; exit 1; }
echo "OK: Found hooks/pre-commit"
echo

echo "[3/6] Checking clang-format on user PATH..."
if ! command -v clang-format >/dev/null 2>&1; then
  echo "ERROR: clang-format was not found on PATH."
  echo "Run tools/coding-standard/scripts/install-user-tools.sh first, or provide clang-format on PATH."
  exit 1
fi
clang-format --version
echo

echo "[4/6] Checking Python..."
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "ERROR: Python 3 was not found on PATH."
  exit 1
fi
"$PYTHON_BIN" --version
echo

echo "[5/6] Checking clang-tidy on PATH..."
if command -v clang-tidy >/dev/null 2>&1; then
  clang-tidy --version
else
  echo "WARNING: clang-tidy was not found on PATH."
  echo "Formatting hooks will still work."
  echo "Linting will be skipped until clang-tidy is installed."
fi
echo

echo "[6/6] Running Python smoke test..."
if "$PYTHON_BIN" "$REPO_ROOT/tools/coding-standard/scripts/clang_format_staged.py" --help >/dev/null 2>&1; then
  echo "OK: Python script invocation succeeded."
else
  echo "WARNING: Smoke test did not return success with --help. Continuing."
fi
