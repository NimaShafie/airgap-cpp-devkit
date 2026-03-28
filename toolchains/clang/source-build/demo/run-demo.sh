#!/usr/bin/env bash
# =============================================================================
# toolchains/clang-source-build/demo/run-demo.sh
#
# PURPOSE: Demonstrate clang-tidy against a C++ file containing intentional
#          issues. Shows what clang-tidy catches before it is wired into a
#          real project.
#
# USAGE:
#   bash toolchains/clang-source-build/demo/run-demo.sh
#
# PREREQUISITES:
#   Linux   : clang-tidy assembled at bin/linux/clang-tidy
#   Windows : clang-tidy built at bin/windows/clang-tidy.exe
#   Run bootstrap.sh first if the binary is not present.
#
# The script does NOT modify demo.cpp. It only reads it.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEMO_SRC="${SCRIPT_DIR}/demo.cpp"

# ---------------------------------------------------------------------------
# Locate clang-tidy binary (platform-aware)
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        CLANG_TIDY="${MODULE_ROOT}/bin/windows/clang-tidy.exe"
        ;;
    *)
        CLANG_TIDY="${MODULE_ROOT}/bin/linux/clang-tidy"
        ;;
esac

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
echo "============================================================"
echo " clang-tidy demo"
echo "============================================================"
echo ""

if [[ ! -x "${CLANG_TIDY}" ]]; then
    echo "[ERROR] clang-tidy not found at: ${CLANG_TIDY}"
    echo ""
    echo "  Run bootstrap first:"
    echo "    bash toolchains/clang-source-build/bootstrap.sh"
    exit 1
fi

TIDY_VER="$("${CLANG_TIDY}" --version 2>/dev/null | head -1)"
echo "  clang-tidy : ${TIDY_VER}"
echo "  Source     : ${DEMO_SRC}"
echo ""

# ---------------------------------------------------------------------------
# Checks to run
# ---------------------------------------------------------------------------
CHECKS=(
    "modernize-use-nullptr"
    "modernize-use-override"
    "modernize-loop-convert"
    "readability-magic-numbers"
    "cppcoreguidelines-init-variables"
    "performance-unnecessary-copy-initialization"
)

CHECKS_ARG=$(IFS=,; echo "${CHECKS[*]}")

echo "  Enabled checks:"
for c in "${CHECKS[@]}"; do
    echo "    • ${c}"
done
echo ""

# ---------------------------------------------------------------------------
# Run clang-tidy
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Build extra-args — platform-aware include paths
# ---------------------------------------------------------------------------
EXTRA_ARGS=(-std=c++17)

case "$(uname -s)" in
    Linux*)
        GCC_INCLUDES="$(gcc -print-file-name=include 2>/dev/null)"
        if [[ -d "${GCC_INCLUDES}" ]]; then
            EXTRA_ARGS+=(-I"${GCC_INCLUDES}")
        fi
        ;;
esac

echo "------------------------------------------------------------"
echo " Diagnostics"
echo "------------------------------------------------------------"
echo ""

# --header-filter set to empty string so we only see issues in demo.cpp itself
# --extra-arg passes C++17 standard so modernize checks work correctly
EXTRA_ARGS_FLAGS=()
for arg in "${EXTRA_ARGS[@]}"; do
    EXTRA_ARGS_FLAGS+=(--extra-arg="${arg}")
done

"${CLANG_TIDY}" \
    "${DEMO_SRC}" \
    --checks="-*,${CHECKS_ARG}" \
    --header-filter="" \
    "${EXTRA_ARGS_FLAGS[@]}" \
    -- 2>&1 || true
# || true: clang-tidy exits non-zero when it finds issues; we want to see them

echo ""
echo "------------------------------------------------------------"
echo " Done."
echo " The issues above are intentional. See demo/demo.cpp for"
echo " comments explaining each one."
echo "------------------------------------------------------------"
echo ""