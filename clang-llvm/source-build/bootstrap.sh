#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# bootstrap.sh — Build clang-format from LLVM source (optional method)
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  This is the SLOW path (~30-60 minutes).                                │
# │                                                                         │
# │  Most developers should use the fast pip/venv method instead:           │
# │    bash clang-llvm-style-formatter/bootstrap.sh                         │
# │                                                                         │
# │  Use this only if:                                                      │
# │    • Python is not available on developer machines                      │
# │    • Policy requires building all tools from source                     │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Builds clang-format from the vendored LLVM 22.1.1 source tarball.
# The compiled binary is placed at bin/<platform>/clang-format[.exe].
# clang-llvm-style-formatter/bootstrap.sh detects it automatically.
#
# Usage:
#   bash clang-llvm-source-build/bootstrap.sh [--rebuild]
#
# Build prerequisites:
#   Windows : Visual Studio 2017/2019/2022 (C++ workload), CMake 3.14+
#   RHEL 8  : GCC 8+, CMake 3.14+, Python 3.6+
#
# See docs/llvm-install-guide.md for detailed instructions.
# =============================================================================

set -euo pipefail

REBUILD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild) REBUILD=true; shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMATTER_DIR="$(cd "${SCRIPT_DIR}/../clang-llvm-style-formatter" 2>/dev/null && pwd)" || \
    FORMATTER_DIR="${SCRIPT_DIR}/../clang-llvm-style-formatter"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows"; OUTPUT_BIN="${SCRIPT_DIR}/bin/windows/clang-format.exe" ;;
    Linux*)                OS="linux";   OUTPUT_BIN="${SCRIPT_DIR}/bin/linux/clang-format" ;;
    *)  echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

echo "=================================================================="
echo "  clang-llvm-source-build"
echo "  Platform : ${OS}"
echo "  Output   : ${OUTPUT_BIN}"
echo "=================================================================="
echo ""
echo "  This build takes 30-60 minutes."
echo "  For a 5-second install, use the pip method instead:"
echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
echo ""

if [[ -x "${OUTPUT_BIN}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1)"
    echo "  Already built: ${VER}"
    echo "  Use --rebuild to force a rebuild."
    echo ""
    echo "  Run the formatter bootstrap to activate:"
    echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
    exit 0
fi

export REBUILD
bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"

[[ -x "${OUTPUT_BIN}" ]] || {
    echo "ERROR: Build completed but binary not found at ${OUTPUT_BIN}" >&2; exit 1
}

VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1)"
echo ""
echo "=================================================================="
echo "  Build complete -- ${VER}"
echo "  Binary: ${OUTPUT_BIN}"
echo "=================================================================="
echo ""
echo "  Now activate the pre-commit hook:"
echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
echo ""