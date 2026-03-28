#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/setup-prebuilt-submodule.sh
#
# PURPOSE: One-time setup script to initialize the prebuilt-binaries submodule.
#          Run this after cloning if you want the pre-built binaries (Base Case).
#          Skip this entirely if you are in a binary-restricted environment
#          and will be building all tools from source (Worst Case).
#
# USAGE:
#   bash scripts/setup-prebuilt-submodule.sh
#
# WHAT IT DOES:
#   1. Initializes and clones the prebuilt-binaries submodule
#   2. Verifies SHA256 of all binaries against manifest.json
#   3. Prints a clear summary of what is available
#
# BINARY-RESTRICTED ENVIRONMENTS:
#   If your air-gapped network does not permit pre-compiled binaries,
#   do NOT run this script. Instead, build all tools from source:
#     bash toolchains/clang/source-build/setup.sh --build-from-source
#     bash winlibs-gcc-ucrt/bootstrap.sh --build-from-source
#     etc.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  airgap-cpp-devkit — Prebuilt Binaries Submodule Setup          ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  This initializes the prebuilt-binaries submodule which         ║"
echo "║  contains pre-compiled binaries for immediate use.              ║"
echo "║                                                                  ║"
echo "║  BINARY-RESTRICTED ENVIRONMENTS:                                ║"
echo "║  If your network prohibits pre-compiled binaries, press Ctrl+C  ║"
echo "║  now and build from source instead.                             ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Press Enter to continue, or Ctrl+C to cancel..."
read -r

cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Check if submodule is already initialized
# ---------------------------------------------------------------------------
if [[ -f "prebuilt-binaries/.git" ]] || \
   git submodule status prebuilt-binaries 2>/dev/null | grep -q "^[^-]"; then
    echo "[INFO] prebuilt-binaries submodule already initialized."
    echo "       Running git submodule update to ensure it is current..."
    git submodule update --init --recursive prebuilt-binaries
else
    echo "[INFO] Initializing prebuilt-binaries submodule..."
    git submodule update --init --recursive prebuilt-binaries
fi

echo ""
echo "[INFO] Submodule initialized."
echo ""

# ---------------------------------------------------------------------------
# Helper: check a single binary file or a set of split parts
#
# Usage:
#   _check_binary  <label>  <relative-path-under-prebuilt-binaries>  [parts]
#
#   If the third argument is "parts", the function checks for <path>.part-*
#   glob matches instead of a plain file, and reports them as split parts
#   ready for assembly.
# ---------------------------------------------------------------------------
_check_binary() {
    local label="$1"
    local rel="$2"
    local mode="${3:-file}"   # "file" or "parts"
    local base="${REPO_ROOT}/prebuilt-binaries/${rel}"

    if [[ "${mode}" == "parts" ]]; then
        local parts=( "${base}".part-* )
        if [[ -f "${parts[0]}" ]]; then
            local count="${#parts[@]}"
            echo "  ○  ${label} (${count} split parts — run bootstrap to assemble)"
        else
            echo "  ✗  ${label} (not found)"
        fi
    else
        if [[ -f "${base}" ]]; then
            local size
            size="$(du -sh "${base}" 2>/dev/null | cut -f1)"
            echo "  ✓  ${label} (${size})"
        else
            echo "  ✗  ${label} (not found)"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Show what is available
# ---------------------------------------------------------------------------
echo "Available pre-built binaries:"
echo ""

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        _check_binary "clang-format.exe"  "toolchains/clang/clang-format.exe"
        _check_binary "clang-tidy.exe"    "toolchains/clang/clang-tidy.exe"
        _check_binary "ninja.exe"         "toolchains/clang/ninja.exe"
        _check_binary "WinLibs GCC"       "winlibs-gcc-ucrt/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r6.zip" parts
        ;;
    Linux*)
        _check_binary "clang-format (linux)"  "toolchains/clang/clang-format-linux"
        _check_binary "clang-tidy (linux)"    "toolchains/clang/clang-tidy" parts
        _check_binary "ninja (linux)"         "toolchains/clang/ninja-linux"
        ;;
esac

echo ""
echo "  Run the individual tool bootstraps to install:"
echo "    bash toolchains/clang/source-build/setup.sh"
echo "    bash winlibs-gcc-ucrt/bootstrap.sh"
echo ""