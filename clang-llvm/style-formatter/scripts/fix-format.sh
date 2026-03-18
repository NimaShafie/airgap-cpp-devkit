#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# fix-format.sh — Auto-apply clang-format to all staged C/C++ files
#
# Run this after the pre-commit hook rejects your commit due to formatting
# violations.  It formats each file in-place and re-stages it so your next
# `git commit` will pass.
#
# Usage (from anywhere inside the host repository):
#   bash .llvm-hooks/scripts/fix-format.sh [--dry-run] [file ...]
#
#   --dry-run   Show what would be changed, but don't modify files.
#   file ...    Specific files to format (defaults to all staged C/C++ files).
# =============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONF="${SUBMODULE_ROOT}/config/hooks.conf"
CONF_LOCAL="${SUBMODULE_ROOT}/.llvm-hooks-local/hooks.conf"

# shellcheck source=/dev/null
source "${CONF}"
# shellcheck source=/dev/null
[[ -f "${CONF_LOCAL}" ]] && source "${CONF_LOCAL}"
# shellcheck source=/dev/null
source "${SUBMODULE_ROOT}/scripts/find-tools.sh"

CLANG_FORMAT_BIN="${CLANG_FORMAT_BIN:-clang-format}"
CPP_EXTENSIONS="${CPP_EXTENSIONS:-cpp,cxx,cc,c,h,hpp,hxx,hh}"

DRY_RUN=false
EXPLICIT_FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [file ...]"
            exit 0 ;;
        *) EXPLICIT_FILES+=("$1"); shift ;;
    esac
done

if ! command -v "${CLANG_FORMAT_BIN}" &>/dev/null; then
    echo "[fix-format] ERROR: '${CLANG_FORMAT_BIN}' not found." >&2
    echo "             Run: ${SUBMODULE_ROOT}/scripts/build-clang-format.sh" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Collect target files
# ---------------------------------------------------------------------------
if [[ ${#EXPLICIT_FILES[@]} -gt 0 ]]; then
    TARGET_FILES=("${EXPLICIT_FILES[@]}")
else
    IFS=',' read -ra EXT_LIST <<< "${CPP_EXTENSIONS}"
    EXT_PATTERN=""
    for ext in "${EXT_LIST[@]}"; do
        EXT_PATTERN="${EXT_PATTERN}|\.${ext}"
    done
    EXT_PATTERN="${EXT_PATTERN:1}"

    mapfile -t TARGET_FILES < <(
        git diff --cached --name-only --diff-filter=ACMR |
        grep -E "(${EXT_PATTERN})$" || true
    )
fi

if [[ ${#TARGET_FILES[@]} -eq 0 ]]; then
    echo "[fix-format] No C/C++ files to format."
    exit 0
fi

echo "[fix-format] Formatting ${#TARGET_FILES[@]} file(s) with ${CLANG_FORMAT_BIN}…"

CHANGED=()
for f in "${TARGET_FILES[@]}"; do
    abs="${REPO_ROOT}/${f}"
    [[ -f "${abs}" ]] || { echo "  skip (not on disk): ${f}"; continue; }

    original="$(cat "${abs}")"
    formatted="$(${CLANG_FORMAT_BIN} --style=file "${abs}" 2>/dev/null)"

    if [[ "${original}" != "${formatted}" ]]; then
        CHANGED+=("${f}")
        if [[ "${DRY_RUN}" == "true" ]]; then
            echo "  [dry-run] would format: ${f}"
            diff <(echo "${original}") <(echo "${formatted}") || true
        else
            echo "${formatted}" > "${abs}"
            git add "${abs}"
            echo "  formatted + re-staged: ${f}"
        fi
    else
        echo "  already clean:         ${f}"
    fi
done

echo ""
if [[ ${#CHANGED[@]} -eq 0 ]]; then
    echo "[fix-format] All files are already correctly formatted ✓"
elif [[ "${DRY_RUN}" == "true" ]]; then
    echo "[fix-format] Dry run complete — ${#CHANGED[@]} file(s) would be changed."
else
    echo "[fix-format] Done — ${#CHANGED[@]} file(s) formatted and re-staged."
    echo "             You can now run: git commit"
fi