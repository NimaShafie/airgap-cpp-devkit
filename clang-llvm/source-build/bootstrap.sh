#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# bootstrap.sh — Install clang-format and clang-tidy from vendored binaries
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  Windows: uses vendored pre-built binaries — no compiler required.      │
# │  Linux:   builds clang-format from source; installs pre-built clang-tidy│
# │                                                                         │
# │  For the fast pip/venv method (clang-format only, both platforms):      │
# │    bash clang-llvm-style-formatter/bootstrap.sh   # ~5 seconds          │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Windows vendored binaries (committed to git, SHA256 verified at install):
#   bin/windows/clang-format.exe   3.1 MB — instant
#   bin/windows/clang-tidy.exe      46 MB — instant
#
# Linux:
#   clang-format  — built from the vendored LLVM 22.1.1 source (~30-60 min)
#   clang-tidy    — reassembled from vendored pre-built split parts (seconds)
#
# Pass --build-from-source to compile from LLVM source on Windows instead.
# Build prerequisites (source build only):
#   Windows : Visual Studio 2017/2019/2022/Insiders with C++ workload
#             Tested: VS Insiders 18 | MSVC toolchain 14.50.35717 | CMake 4.1.2
#   RHEL 8  : GCC 8+ (gcc-c++), CMake 3.14+, Python 3.6+
#
# Output binaries:
#   bin/linux/clang-format
#   bin/linux/clang-tidy       (reassembled from vendored parts)
#   bin/windows/clang-format.exe (vendored pre-built)
#   bin/windows/clang-tidy.exe   (vendored pre-built)
#
# Usage:
#   bash clang-llvm-source-build/bootstrap.sh [--rebuild] [--build-from-source]
#
# Options:
#   --rebuild            Force re-verify/rebuild of all binaries
#   --build-from-source  Windows only: build both tools from LLVM source
#
# See docs/llvm-install-guide.md for full prerequisites and troubleshooting.
# =============================================================================

set -euo pipefail

REBUILD=false
BUILD_FROM_SOURCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild)           REBUILD=true; shift ;;
        --build-from-source) BUILD_FROM_SOURCE=true; shift ;;
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
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)                OS="linux"   ;;
    *)  echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/clang-llvm"

# Source shared install-mode library
source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "clang-llvm" "22.1.1"
install_log_capture_start
OUTPUT_FMT_WIN="${PREBUILT_DIR}/clang-format.exe"
OUTPUT_TIDY_WIN="${PREBUILT_DIR}/clang-tidy.exe"
OUTPUT_FMT_LIN="${SCRIPT_DIR}/bin/linux/clang-format"
OUTPUT_TIDY_LIN="${SCRIPT_DIR}/bin/linux/clang-tidy"

case "${OS}" in
    windows) OUTPUT_FMT="${OUTPUT_FMT_WIN}"; OUTPUT_TIDY="${OUTPUT_TIDY_WIN}" ;;
    linux)   OUTPUT_FMT="${OUTPUT_FMT_LIN}"; OUTPUT_TIDY="${OUTPUT_TIDY_LIN}" ;;
esac

echo "=================================================================="
echo "  clang-llvm-source-build"
echo "  Platform     : ${OS}"
echo "  clang-format : ${OUTPUT_FMT}"
echo "  clang-tidy   : ${OUTPUT_TIDY}"
echo "=================================================================="
echo ""

# ==========================================================================
# PART 1 — clang-format
#   Windows: verify vendored pre-built binary (instant)
#   Linux:   build from source (~30-60 min)
# ==========================================================================
echo "------------------------------------------------------------------"
echo "  [1/2] clang-format"
echo "------------------------------------------------------------------"
echo ""

if [[ -x "${OUTPUT_FMT}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_FMT}" --version 2>/dev/null | head -1)"
    echo "  Already present: ${VER}"
    echo "  Use --rebuild to force re-verification."
else
    case "${OS}" in
        windows)
            if [[ "${BUILD_FROM_SOURCE}" == "true" ]]; then
                echo "  Windows: building from source (--build-from-source)."
                echo "  This build takes 30-60 minutes."
                echo ""
                export REBUILD
                bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"
            else
                echo "  Windows: verifying vendored pre-built binary..."
                echo ""
                bash "${SCRIPT_DIR}/scripts/verify-clang-format-windows.sh"
            fi
            ;;
        linux)
            echo "  Linux: building from source (~30-60 minutes)."
            echo "  For a 5-second install, use the pip method instead:"
            echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
            echo ""
            export REBUILD
            bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"
            ;;
    esac

    [[ -x "${OUTPUT_FMT}" ]] || {
        echo "ERROR: clang-format not found at ${OUTPUT_FMT}" >&2
        exit 1
    }
    VER="$("${OUTPUT_FMT}" --version 2>/dev/null | head -1)"
    echo ""
    echo "  Ready: ${VER}"
fi

echo ""

# ==========================================================================
# PART 2 — clang-tidy
#   Linux  : reassemble pre-built vendored binary from split parts
#   Windows: verify vendored pre-built binary (or build from source)
# ==========================================================================
echo "------------------------------------------------------------------"
echo "  [2/2] clang-tidy"
echo "------------------------------------------------------------------"
echo ""

if [[ -x "${OUTPUT_TIDY}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | grep "LLVM version" | head -1)"
    echo "  Already present: ${VER}"
    echo "  Use --rebuild to force re-verification."
else
    case "${OS}" in
        linux)
            echo "  Linux: reassembling from vendored pre-built parts..."
            echo ""
            bash "${SCRIPT_DIR}/scripts/reassemble-clang-tidy.sh"

            [[ -x "${OUTPUT_TIDY}" ]] || {
                echo "ERROR: clang-tidy not found at ${OUTPUT_TIDY} after reassembly." >&2
                exit 1
            }
            ;;
        windows)
            if [[ "${BUILD_FROM_SOURCE}" == "true" ]]; then
                echo "  Windows: building from source (--build-from-source)."
                echo "  Expected time: ~60-120 min first build."
                echo ""
                bash "${SCRIPT_DIR}/scripts/build-clang-tidy.sh" \
                    $([[ "${REBUILD}" == "true" ]] && echo "--rebuild" || true)
            else
                echo "  Windows: verifying vendored pre-built binary..."
                echo ""
                bash "${SCRIPT_DIR}/scripts/verify-clang-tidy-windows.sh"
            fi

            [[ -x "${OUTPUT_TIDY}" ]] || {
                echo "ERROR: clang-tidy not found at ${OUTPUT_TIDY}." >&2
                exit 1
            }
            ;;
    esac

    VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | grep "LLVM version" | head -1)"
    echo ""
    echo "  Ready: ${VER}"
fi

echo ""

# ==========================================================================
# Summary
# ==========================================================================
# ---------------------------------------------------------------------------
# Install binaries to system/user path
# ---------------------------------------------------------------------------
mkdir -p "${INSTALL_BIN_DIR}"

_install_bin() {
    local src="$1" name="$2"
    if [[ -x "${src}" ]]; then
        cp -f "${src}" "${INSTALL_BIN_DIR}/${name}"
        chmod +x "${INSTALL_BIN_DIR}/${name}"
        echo "  Installed: ${INSTALL_BIN_DIR}/${name}"
    fi
}

case "${OS}" in
    windows)
        _install_bin "${OUTPUT_FMT}"  "clang-format.exe"
        _install_bin "${OUTPUT_TIDY}" "clang-tidy.exe"
        ;;
    linux)
        _install_bin "${OUTPUT_FMT}"  "clang-format"
        _install_bin "${OUTPUT_TIDY}" "clang-tidy"
        ;;
esac

install_receipt_write "success"     "clang-format:${INSTALL_BIN_DIR}/clang-format"     "clang-tidy:${INSTALL_BIN_DIR}/clang-tidy"

install_mode_print_footer "success"     "clang-format:${INSTALL_BIN_DIR}/clang-format"     "clang-tidy:${INSTALL_BIN_DIR}/clang-tidy"

echo "=================================================================="
echo "  All done."
echo "  clang-format : ${OUTPUT_FMT}"
echo "  clang-tidy   : ${OUTPUT_TIDY}"
echo "=================================================================="
echo ""
echo "  Now activate the pre-commit hook:"
echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
echo ""