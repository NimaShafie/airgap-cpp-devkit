#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang/style-formatter/bootstrap.sh
#
# Installs clang-format via Python venv (from vendored wheels) and wires
# the pre-commit hook into the host repository.
#
# USAGE:
#   bash toolchains/clang/style-formatter/bootstrap.sh [--force]
#
# OPTIONS:
#   --force    Overwrite existing hook and recreate venv without prompting.
# =============================================================================

set -euo pipefail

# Load install-mode helpers if available, otherwise stub progress functions
REPO_ROOT_SF="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -f "${REPO_ROOT_SF}/scripts/install-mode.sh" ]]; then
    source "${REPO_ROOT_SF}/scripts/install-mode.sh" 2>/dev/null || true
fi
if ! command -v im_progress_start &>/dev/null; then
    im_progress_start() { echo "  [....] ${1:-Working}..."; }
    im_progress_stop()  { echo "  [OK]  ${1:-Done}"; }
fi

FORCE=""
FORCE_BOOL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE="--force"; FORCE_BOOL=true; shift ;;
        -h|--help) echo "Usage: $0 [--force]"; exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
IN_GIT_REPO=false
[[ -n "${REPO_ROOT}" ]] && IN_GIT_REPO=true

_find_tool() {
    local tool="$1"
    if command -v "${tool}" &>/dev/null; then
        command -v "${tool}"; return 0
    fi
    for ver in 18 17 16 15 14; do
        if command -v "${tool}-${ver}" &>/dev/null; then
            command -v "${tool}-${ver}"; return 0
        fi
    done
    for candidate in \
        "${SCRIPT_DIR}/.venv/Scripts/${tool}.exe" \
        "${SCRIPT_DIR}/.venv/bin/${tool}"; do
        [[ -x "${candidate}" ]] && { echo "${candidate}"; return 0; }
    done
    for candidate in \
        "${SCRIPT_DIR}/../source-build/bin/windows/${tool}.exe" \
        "${SCRIPT_DIR}/../source-build/bin/linux/${tool}" \
        "${SCRIPT_DIR}/bin/windows/${tool}.exe" \
        "${SCRIPT_DIR}/bin/linux/${tool}"; do
        [[ -x "${candidate}" ]] && { echo "${candidate}"; return 0; }
    done
    return 1
}

_tool_version() {
    local bin="$1" tool="$2"
    "${bin}" --version 2>/dev/null | head -1
}

echo "=================================================================="
echo "  toolchains/clang-style-formatter — Developer Bootstrap"
echo "  Install method: Python venv (pip)"
echo "=================================================================="
echo ""

# Step 1 — Initialise submodules
if [[ "${IN_GIT_REPO}" == "true" ]]; then
    echo "[bootstrap] Step 1/4: Initialising git submodules..."
    im_progress_start "Initialising submodules" 2>/dev/null || true
    git -C "${REPO_ROOT}" submodule update --init --recursive
    im_progress_stop "Submodules ready" 2>/dev/null || true
else
    echo "[bootstrap] Step 1/4: Not inside a git repository — skipping submodule init."
fi
echo ""

# Step 2 — Check for clang-format
echo "[bootstrap] Step 2/4: Checking for clang-format..."
echo ""
CF_PATH=""
CF_OK=false
if CF_PATH="$(_find_tool "clang-format" 2>/dev/null)"; then
    CF_VER="$(_tool_version "${CF_PATH}" "clang-format")"
    CF_OK=true
    echo "  [OK] clang-format : ${CF_VER}"
    echo "       Location     : ${CF_PATH}"
else
    echo "  [!!] clang-format : not found"
fi
echo ""

# Step 3 — Install via pip/venv if needed
if [[ "${CF_OK}" == "true" && "${FORCE_BOOL}" == "false" ]]; then
    echo "[bootstrap] Step 3/4: clang-format available — skipping install."
else
    echo "[bootstrap] Step 3/4: Installing clang-format via Python venv..."
    echo ""

    WHEELS_PRESENT=false
    for f in "${SCRIPT_DIR}/python-packages"/clang_format-*.whl; do
        [[ -f "${f}" ]] && { WHEELS_PRESENT=true; break; }
    done

    if [[ "${WHEELS_PRESENT}" == "false" ]]; then
        echo "  ERROR: No clang-format wheels found in python-packages/" >&2
        echo "  Run: bash ${SCRIPT_DIR}/scripts/fetch-wheels.sh" >&2
        exit 1
    fi

    VENV_ARGS=""
    [[ "${FORCE_BOOL}" == "true" ]] && VENV_ARGS="--force"

    im_progress_start "Installing clang-format via pip venv"
    if bash "${SCRIPT_DIR}/scripts/install-venv.sh" ${VENV_ARGS}; then
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*) _VENV_CF="${SCRIPT_DIR}/.venv/Scripts/clang-format.exe" ;;
            *)                    _VENV_CF="${SCRIPT_DIR}/.venv/bin/clang-format" ;;
        esac
        if [[ -x "${_VENV_CF}" ]]; then
            CF_PATH="${_VENV_CF}"
            CF_OK=true
            CF_VER="$(_tool_version "${CF_PATH}" "clang-format")"
            im_progress_stop "clang-format installed: ${CF_VER}"
        else
            im_progress_stop "WARNING: venv installed but binary not found"
        fi
    else
        im_progress_stop "FAILED"
        echo "  ERROR: pip/venv install failed." >&2
        exit 1
    fi
fi
echo ""

# Step 4 — Install the pre-commit hook
if [[ "${IN_GIT_REPO}" == "true" ]]; then
    echo "[bootstrap] Step 4/4: Installing pre-commit hook..."
    echo "  [....] Installing pre-commit hook..."
    bash "${SCRIPT_DIR}/scripts/install-hooks.sh" ${FORCE} 2>&1 | sed 's/^/            /' || true
    echo "  [OK]  Pre-commit hook installed"
else
    echo "[bootstrap] Step 4/4: Not inside a git repository — skipping hook install."
fi
echo ""

echo "=================================================================="
echo "  Bootstrap complete"
echo "=================================================================="
echo ""
echo "  clang-format : ${CF_PATH:-not found}"
if [[ "${IN_GIT_REPO}" == "true" ]]; then
    echo "  pre-commit   : $(
        [[ -f "${REPO_ROOT}/.git/hooks/pre-commit" ]] && echo "installed" || echo "MISSING"
    )"
    echo ""
    echo "  Every 'git commit' will now enforce LLVM C++ style."
    echo "  To fix violations:  bash ${SCRIPT_DIR}/scripts/fix-format.sh"
    echo "  To run smoke test:  bash ${SCRIPT_DIR}/scripts/smoke-test.sh"
else
    echo "  pre-commit   : not installed (no git repository detected)"
fi
echo ""