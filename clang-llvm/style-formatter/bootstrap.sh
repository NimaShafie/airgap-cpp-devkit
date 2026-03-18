#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# bootstrap.sh — One-command developer onboarding
#
# Installs clang-format via Python venv (from vendored wheels in
# python-packages/) and wires the pre-commit hook into the host repository.
#
# This is the FAST path (~5 seconds). No compiler, no Visual Studio,
# no CMake required. Python 3.8+ must be available on PATH.
#
# Can be run from inside or outside a git repository:
#   • Inside a git repo  — installs clang-format AND the pre-commit hook.
#   • Outside a git repo — installs clang-format only (no hook to install).
#
# If you need to build clang-format from LLVM source instead, see:
#   ../clang-llvm-source-build/bootstrap.sh
#
# Usage:
#   bash clang-llvm-style-formatter/bootstrap.sh [--force]
#
# Options:
#   --force    Overwrite existing hook and recreate venv without prompting.
# =============================================================================

set -euo pipefail

FORCE=""
FORCE_BOOL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE="--force"; FORCE_BOOL=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Detect whether we are inside a git repository (optional — not required)
# ---------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
IN_GIT_REPO=false
[[ -n "${REPO_ROOT}" ]] && IN_GIT_REPO=true

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_find_tool() {
    local tool="$1"
    # System PATH (plain name + versioned suffixes)
    if command -v "${tool}" &>/dev/null; then
        command -v "${tool}"; return 0
    fi
    for ver in 18 17 16 15 14; do
        if command -v "${tool}-${ver}" &>/dev/null; then
            command -v "${tool}-${ver}"; return 0
        fi
    done
    # pip venv (preferred local install)
    for candidate in \
        "${SCRIPT_DIR}/.venv/Scripts/${tool}.exe" \
        "${SCRIPT_DIR}/.venv/bin/${tool}"; do
        [[ -x "${candidate}" ]] && { echo "${candidate}"; return 0; }
    done
    # Built binary from LLVM source (fallback)
    for candidate in \
        "${SCRIPT_DIR}/../clang-llvm-source-build/bin/windows/${tool}.exe" \
        "${SCRIPT_DIR}/../clang-llvm-source-build/bin/linux/${tool}" \
        "${SCRIPT_DIR}/bin/windows/${tool}.exe" \
        "${SCRIPT_DIR}/bin/linux/${tool}"; do
        [[ -x "${candidate}" ]] && { echo "${candidate}"; return 0; }
    done
    return 1
}

_tool_version() {
    local bin="$1" tool="$2"
    case "${tool}" in
        clang-format) "${bin}" --version 2>/dev/null | head -1 ;;
        ninja)        "${bin}" --version 2>/dev/null ;;
        *)            "${bin}" --version 2>/dev/null | head -1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo "=================================================================="
echo "  clang-llvm-style-formatter — Developer Bootstrap"
echo "  Install method: Python venv (pip)"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1 — Initialise submodules (only if inside a git repo)
# ---------------------------------------------------------------------------
if [[ "${IN_GIT_REPO}" == "true" ]]; then
    echo "[bootstrap] Step 1/4: Initialising git submodules..."
    git -C "${REPO_ROOT}" submodule update --init --recursive
    echo "            Done."
else
    echo "[bootstrap] Step 1/4: Not inside a git repository — skipping submodule init."
    echo "            clang-format will still be installed for standalone use."
fi
echo ""

# ---------------------------------------------------------------------------
# Step 2 — Check for clang-format
# ---------------------------------------------------------------------------
echo "[bootstrap] Step 2/4: Checking for clang-format..."
echo ""

CF_PATH=""
CF_OK=false

if CF_PATH="$(_find_tool "clang-format" 2>/dev/null)"; then
    CF_VER="$(_tool_version "${CF_PATH}" "clang-format")"
    CF_OK=true
    echo "  ✓  clang-format : ${CF_VER}"
    echo "     Location     : ${CF_PATH}"
else
    echo "  ✗  clang-format : not found"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 3 — Install via pip/venv if needed
# ---------------------------------------------------------------------------
if [[ "${CF_OK}" == "true" && "${FORCE_BOOL}" == "false" ]]; then
    echo "[bootstrap] Step 3/4: clang-format available — skipping install."
else
    echo "[bootstrap] Step 3/4: Installing clang-format via Python venv..."
    echo ""
    echo "  ── pip + venv method ──────────────────────────────────────────"
    echo "  Installs clang-format from vendored .whl files in python-packages/"
    echo "  No network access, no compiler, no admin rights required."
    echo "  Requires: Python 3.8+ on PATH"
    echo "  Time    : ~5 seconds"
    echo ""

    VENV_SCRIPT="${SCRIPT_DIR}/scripts/install-venv.sh"
    WHEELS_PRESENT=false
    for f in "${SCRIPT_DIR}/python-packages"/clang_format-*.whl; do
        [[ -f "${f}" ]] && { WHEELS_PRESENT=true; break; }
    done

    if [[ "${WHEELS_PRESENT}" == "false" ]]; then
        echo "  ERROR: No clang-format wheels found in python-packages/" >&2
        echo "" >&2
        echo "  Expected files:" >&2
        echo "    python-packages/clang_format-*-win_amd64.whl" >&2
        echo "    python-packages/clang_format-*-manylinux*.whl" >&2
        echo "" >&2
        echo "  To fetch wheels (requires internet, run once on connected machine):" >&2
        echo "    bash ${SCRIPT_DIR}/scripts/fetch-wheels.sh" >&2
        echo "" >&2
        echo "  Alternatively, build clang-format from LLVM source:" >&2
        echo "    bash $(cd "${SCRIPT_DIR}/.." && pwd)/clang-llvm-source-build/bootstrap.sh" >&2
        exit 1
    fi

    VENV_ARGS=""
    [[ "${FORCE_BOOL}" == "true" ]] && VENV_ARGS="--force"

    if bash "${VENV_SCRIPT}" ${VENV_ARGS}; then
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*) _VENV_CF="${SCRIPT_DIR}/.venv/Scripts/clang-format.exe" ;;
            *)                    _VENV_CF="${SCRIPT_DIR}/.venv/bin/clang-format" ;;
        esac
        if [[ -x "${_VENV_CF}" ]]; then
            CF_PATH="${_VENV_CF}"
            CF_OK=true
            CF_VER="$(_tool_version "${CF_PATH}" "clang-format")"
            echo ""
            echo "  ✓  clang-format installed: ${CF_VER}"
            echo "     Location: ${CF_PATH}"
        fi
    else
        echo "" >&2
        echo "  ERROR: pip/venv install failed." >&2
        echo "" >&2
        echo "  To build from LLVM source instead (~30-60 min):" >&2
        echo "    bash $(cd "${SCRIPT_DIR}/.." && pwd)/clang-llvm-source-build/bootstrap.sh" >&2
        exit 1
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4 — Install the pre-commit hook (only if inside a git repo)
# ---------------------------------------------------------------------------
if [[ "${IN_GIT_REPO}" == "true" ]]; then
    echo "[bootstrap] Step 4/4: Installing pre-commit hook..."
    bash "${SCRIPT_DIR}/scripts/install-hooks.sh" ${FORCE} 2>&1 | sed 's/^/            /'
else
    echo "[bootstrap] Step 4/4: Not inside a git repository — skipping hook install."
    echo "            To install the hook later, run from inside your project:"
    echo "            bash ${SCRIPT_DIR}/scripts/install-hooks.sh"
fi
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=================================================================="
echo "  Bootstrap complete ✓"
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
    echo ""
    echo "  clang-format is ready for standalone use."
    echo "  To install the pre-commit hook, run from inside a git repository:"
    echo "    bash ${SCRIPT_DIR}/scripts/install-hooks.sh"
fi
echo ""