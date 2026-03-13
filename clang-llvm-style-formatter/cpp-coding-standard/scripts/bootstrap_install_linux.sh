#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: This script must be run inside a Git repository."
  exit 1
fi
cd "$REPO_ROOT"
bash tools/coding-standard/scripts/sync-root-clang-format.sh
bash tools/coding-standard/scripts/install-user-tools.sh
bash tools/coding-standard/scripts/install-hooks.sh
echo
echo "C++ coding standard setup finished successfully."
