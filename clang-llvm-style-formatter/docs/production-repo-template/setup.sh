#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# setup.sh — One-command developer onboarding for LLVM C++ style enforcement
#
# Run this once after cloning the repository. That is all.
#
#   bash setup.sh
#
# What it does:
#   1. Initialises the clang-llvm-style-formatter submodule
#   2. Installs clang-format from vendored Python wheels (~5 seconds)
#   3. Installs the pre-commit hook into .git/hooks/
#
# After this, every 'git commit' automatically enforces LLVM C++ style.
# No network access, no admin rights, no compiler required.
#
# Prerequisites:
#   Windows 11  — Python 3.8+, Git Bash (MINGW64)
#   RHEL 8      — Python 3.8+, Bash 4.x
#
# To re-run (e.g. after a fresh clone on a new machine):
#   bash setup.sh
#
# To force reinstall of clang-format and the hook:
#   bash setup.sh --force
# =============================================================================

set -euo pipefail

FORCE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE="--force"; shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: Not inside a git repository." >&2
    exit 1
}

SUBMODULE_PATH="tools/clang-llvm-style-formatter"
BOOTSTRAP="${REPO_ROOT}/${SUBMODULE_PATH}/bootstrap.sh"

# ---------------------------------------------------------------------------
# Ensure the submodule is initialised
# ---------------------------------------------------------------------------
if [[ ! -f "${BOOTSTRAP}" ]]; then
    echo "[setup] Initialising submodule ${SUBMODULE_PATH}..."
    git -C "${REPO_ROOT}" submodule update --init --recursive "${SUBMODULE_PATH}"
fi

if [[ ! -f "${BOOTSTRAP}" ]]; then
    echo "ERROR: Could not find ${BOOTSTRAP}" >&2
    echo "       Ensure the submodule was added correctly." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Delegate to the formatter's bootstrap
# ---------------------------------------------------------------------------
exec bash "${BOOTSTRAP}" ${FORCE}