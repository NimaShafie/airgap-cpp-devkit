#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — One-command developer onboarding
#
# Run this once after cloning any host repository that uses
# clang-llvm-style-formatter as a submodule.
#
# Flow:
#   1. Initialise git submodules.
#   2. Check system PATH for clang-format AND ninja.
#      - Found both  → nothing to build, proceed to hook install.
#      - Found some  → report what's missing.
#      - Found none  → report missing.
#   3. If anything is missing, show what was found vs. what was missing,
#      then ask: "Install from vendored source? [y/N]"
#      - Yes → build whatever is missing from the committed tarballs.
#      - No  → print a clear message and EXIT with error (non-zero).
#              The hook is NOT installed when the user declines.
#   4. Install the pre-commit hook.
#   5. Print a health summary.
#
# Usage:
#   bash .llvm-hooks/bootstrap.sh [--force] [--skip-path-setup]
#
# Options:
#   --force           Overwrite an existing hook without prompting.
#   --skip-path-setup Skip the system PATH scan (jump straight to build offer).
# =============================================================================

set -euo pipefail

FORCE=""
SKIP_PATH_SETUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)           FORCE="--force";      shift ;;
        --skip-path-setup) SKIP_PATH_SETUP=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--force] [--skip-path-setup]"
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "[bootstrap] ERROR: Not inside a git repository." >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Find a tool on PATH or at the vendored bin/ locations
_find_tool() {
    local tool="$1"
    # System PATH (plain name + versioned suffixes)
    if command -v "${tool}" &>/dev/null; then
        command -v "${tool}"
        return 0
    fi
    for ver in 18 17 16 15 14; do
        if command -v "${tool}-${ver}" &>/dev/null; then
            command -v "${tool}-${ver}"
            return 0
        fi
    done
    # Vendored bin/
    for candidate in \
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
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1 — Initialise submodules
# ---------------------------------------------------------------------------
echo "[bootstrap] Step 1/4: Initialising git submodules…"
git -C "${REPO_ROOT}" submodule update --init --recursive
echo "            Done."
echo ""

# ---------------------------------------------------------------------------
# Step 2 — Check system/PATH for all required tools
# ---------------------------------------------------------------------------
echo "[bootstrap] Step 2/4: Checking system for required tools…"
echo ""

CF_PATH=""
NINJA_PATH=""

# clang-format
if CF_PATH="$(_find_tool "clang-format" 2>/dev/null)"; then
    CF_VER="$(_tool_version "${CF_PATH}" "clang-format")"
    echo "  ✓  clang-format : ${CF_VER}"
    echo "     Location     : ${CF_PATH}"
else
    echo "  ✗  clang-format : not found on PATH or in bin/"
fi

echo ""

# ninja
if NINJA_PATH="$(_find_tool "ninja" 2>/dev/null)"; then
    NINJA_VER="$(_tool_version "${NINJA_PATH}" "ninja")"
    echo "  ✓  ninja        : v${NINJA_VER}"
    echo "     Location     : ${NINJA_PATH}"
else
    echo "  ✗  ninja        : not found on PATH or in bin/"
    echo "     (ninja dramatically speeds up the clang-format build;"
    echo "      it will be built from vendored source if needed)"
fi

echo ""

# Determine what needs to be done
CF_OK=false
NINJA_OK=false
[[ -n "${CF_PATH}" ]]    && CF_OK=true
[[ -n "${NINJA_PATH}" ]] && NINJA_OK=true

# If clang-format is already present, nothing more to do
if [[ "${CF_OK}" == "true" ]]; then
    echo "[bootstrap] Step 3/4: clang-format available — no build required."
    echo ""
else
    # ---------------------------------------------------------------------------
    # Step 3 — Tools missing: show summary, ask user whether to proceed
    # ---------------------------------------------------------------------------
    echo "[bootstrap] Step 3/4: One or more tools are missing."
    echo ""

    # Summarise what's needed
    echo "  ── What will be built ─────────────────────────────────────────"
    [[ "${CF_OK}"    == "false" ]] && echo "    • clang-format  (from llvm-src/   — ~30–60 min)"
    [[ "${NINJA_OK}" == "false" ]] && echo "    • ninja         (from ninja-src/  — ~30 sec)"
    echo ""
    echo "  ── Prerequisites required ─────────────────────────────────────"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            echo "    • Visual Studio 2017/2019/2022 (C++ workload)"
            echo "    • CMake 3.14+  (bundled with VS 2019+)"
            echo "    • Run from:    x64 Native Tools Command Prompt for VS"
            ;;
        *)
            echo "    • GCC/G++ 8+  (gcc-c++ package)"
            echo "    • CMake 3.14+ (cmake package)"
            ;;
    esac
    echo "  ── ────────────────────────────────────────────────────────────"
    echo ""

    # Verify the vendored tarballs are present before asking
    LLVM_TARBALL=""
    for f in "${SCRIPT_DIR}/llvm-src"/llvm-project-*.src.tar.xz \
              "${SCRIPT_DIR}/llvm-src"/llvm-project-*.src.tar.gz; do
        [[ -f "${f}" ]] && { LLVM_TARBALL="${f}"; break; }
    done

    NINJA_TARBALL=""
    for f in "${SCRIPT_DIR}/ninja-src"/ninja-*.tar.gz \
              "${SCRIPT_DIR}/ninja-src"/ninja-*.tar.xz; do
        [[ -f "${f}" ]] && { NINJA_TARBALL="${f}"; break; }
    done

    # If tarballs are missing, we can't proceed — hard error
    TARBALLS_OK=true
    if [[ "${CF_OK}" == "false" && -z "${LLVM_TARBALL}" ]]; then
        echo "  ERROR: LLVM tarball not found in llvm-src/." >&2
        echo "         Expected: llvm-src/llvm-project-22.1.1.src.tar.xz" >&2
        echo "         The tarball must be committed to the repository." >&2
        TARBALLS_OK=false
    fi
    if [[ "${NINJA_OK}" == "false" && -z "${NINJA_TARBALL}" ]]; then
        echo "  WARNING: Ninja tarball not found in ninja-src/ — will try make instead." >&2
    fi

    if [[ "${TARBALLS_OK}" == "false" ]]; then
        echo "" >&2
        echo "  Bootstrap cannot continue. Contact your repository maintainer." >&2
        exit 1
    fi

    # ── Ask the user ──────────────────────────────────────────────────────
    read -r -p "  Install missing tools from vendored source? [y/N] " user_choice
    echo ""

    if [[ "${user_choice,,}" != "y" ]]; then
        echo "  ┌─────────────────────────────────────────────────────────┐"
        echo "  │  Installation declined.                                 │"
        echo "  │                                                         │"
        echo "  │  clang-format is required for the pre-commit hook.      │"
        echo "  │  The hook has NOT been installed.                       │"
        echo "  │                                                         │"
        echo "  │  To install later, rerun:                               │"
        echo "  │    bash .llvm-hooks/bootstrap.sh                        │"
        echo "  └─────────────────────────────────────────────────────────┘"
        echo ""
        exit 1
    fi

    # ── User said yes — build what's missing ─────────────────────────────
    echo ""

    # Build ninja first if missing (clang-format build needs it)
    if [[ "${NINJA_OK}" == "false" && -n "${NINJA_TARBALL}" ]]; then
        echo "  Building Ninja from vendored source…"
        echo ""
        bash "${SCRIPT_DIR}/scripts/build-ninja.sh"
        echo ""
        # Pick up newly built binary
        NINJA_PATH="$(_find_tool "ninja" 2>/dev/null || true)"
        [[ -n "${NINJA_PATH}" ]] && NINJA_OK=true
    fi

    # Build clang-format
    echo "  Building clang-format from vendored source…"
    echo ""
    bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"
    echo ""

    # Verify the result
    if CF_PATH="$(_find_tool "clang-format" 2>/dev/null)"; then
        CF_OK=true
        CF_VER="$(_tool_version "${CF_PATH}" "clang-format")"
        echo "  ✓  clang-format built: ${CF_VER}"
        echo "     Location: ${CF_PATH}"
    else
        echo "  ERROR: Build completed but clang-format still not found." >&2
        echo "         Run: bash ${SCRIPT_DIR}/scripts/verify-tools.sh" >&2
        exit 1
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4 — Install the pre-commit hook
# ---------------------------------------------------------------------------
echo "[bootstrap] Step 4/4: Installing pre-commit hook…"
# shellcheck disable=SC2086
bash "${SCRIPT_DIR}/scripts/install-hooks.sh" ${FORCE} 2>&1 | sed 's/^/            /'
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=================================================================="
echo "  Bootstrap complete ✓"
echo "=================================================================="
echo ""
_yn() { [[ "$1" == "true" ]] && echo "YES" || echo "NO  ← action needed"; }
echo "  clang-format : $(_yn "${CF_OK}")  ${CF_PATH:-(not found)}"
echo "  ninja        : $(_yn "${NINJA_OK}")  ${NINJA_PATH:-(not found — make was used)}"
echo "  pre-commit   : $(
    [[ -f "${REPO_ROOT}/.git/hooks/pre-commit" ]] && echo "installed" || echo "MISSING"
)"
echo ""