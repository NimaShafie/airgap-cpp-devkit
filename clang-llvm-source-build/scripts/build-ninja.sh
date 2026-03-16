#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# build-ninja.sh — Build the Ninja build system from the vendored source
#                  tarball in ninja-src/.
#
# Ninja is dramatically faster than make for building LLVM:
#   - Typically 2–3x faster compile times
#   - Significantly lower peak RAM during link steps
#   - Better incremental build support
#
# The compiled binary is placed at:
#   bin/linux/ninja       (Linux)
#   bin/windows/ninja.exe (Windows, only if not already found in VS)
#
# Called automatically by build-clang-format.sh when Ninja is not on PATH.
# Can also be run directly.
#
# Prerequisites:
#   Linux  : g++ (gcc-c++ package)
#   Windows: MSVC (run from x64 Native Tools Command Prompt for VS)
#
# Usage:
#   bash scripts/build-ninja.sh [--force]
#
# Options:
#   --force    Rebuild even if ninja binary already exists.
# =============================================================================

set -euo pipefail

FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NINJA_SRC_DIR="${SUBMODULE_ROOT}/ninja-src"

# ---------------------------------------------------------------------------
# Detect OS and set output paths
# ---------------------------------------------------------------------------
_detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)                echo "linux"   ;;
        Darwin*)               echo "macos"   ;;
        *)                     echo "unknown" ;;
    esac
}
OS="$(_detect_os)"

case "${OS}" in
    windows)
        BIN_DIR="${SUBMODULE_ROOT}/bin/windows"
        OUTPUT_BIN="${BIN_DIR}/ninja.exe"
        ;;
    *)
        BIN_DIR="${SUBMODULE_ROOT}/bin/linux"
        OUTPUT_BIN="${BIN_DIR}/ninja"
        ;;
esac

# ---------------------------------------------------------------------------
# Check if already built
# ---------------------------------------------------------------------------
if [[ -x "${OUTPUT_BIN}" && "${FORCE}" == "false" ]]; then
    echo "[build-ninja] Already built: ${OUTPUT_BIN}"
    echo "              Use --force to rebuild."
    exit 0
fi

# ---------------------------------------------------------------------------
# Find the committed Ninja tarball
# ---------------------------------------------------------------------------
TARBALL=""
for f in "${NINJA_SRC_DIR}"/ninja-*.tar.gz \
          "${NINJA_SRC_DIR}"/ninja-*.tar.xz; do
    [[ -f "${f}" ]] && { TARBALL="${f}"; break; }
done

if [[ -z "${TARBALL}" ]]; then
    echo "" >&2
    echo "ERROR: No Ninja tarball found in ninja-src/." >&2
    echo "  Expected: ninja-src/ninja-<version>.tar.gz" >&2
    echo "  This file should be committed in the repository." >&2
    exit 1
fi

NINJA_VERSION="$(basename "${TARBALL}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

echo "=================================================================="
echo "  build-ninja.sh"
echo "  Version  : ${NINJA_VERSION}"
echo "  Platform : ${OS}"
echo "  Output   : ${OUTPUT_BIN}"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Check for a C++ compiler
# ---------------------------------------------------------------------------
CXX_BIN=""
if [[ "${OS}" == "windows" ]]; then
    if command -v cl &>/dev/null; then
        CXX_BIN="cl"
        echo "  Compiler : MSVC ($(cl 2>&1 | head -1))"
    else
        echo "ERROR: MSVC (cl.exe) not found." >&2
        echo "  Run from an x64 Native Tools Command Prompt for VS." >&2
        exit 1
    fi
else
    for cxx in g++ c++ clang++; do
        if command -v "${cxx}" &>/dev/null; then
            CXX_BIN="${cxx}"
            echo "  Compiler : ${cxx} ($(${cxx} --version | head -1))"
            break
        fi
    done
    [[ -n "${CXX_BIN}" ]] || {
        echo "ERROR: No C++ compiler found (g++, c++, or clang++)." >&2
        echo "  Install: sudo dnf install gcc-c++" >&2
        exit 1
    }
fi

# ---------------------------------------------------------------------------
# Extract Ninja source
# ---------------------------------------------------------------------------
BUILD_DIR="${NINJA_SRC_DIR}/build"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo ""
echo "[Step 1/2] Extracting Ninja source…"
tar -xf "${TARBALL}" -C "${BUILD_DIR}"

# Find the extracted directory
EXTRACTED=""
for d in "${BUILD_DIR}"/ninja-*; do
    [[ -d "${d}" ]] && { EXTRACTED="${d}"; break; }
done
[[ -n "${EXTRACTED}" ]] || {
    echo "ERROR: Extraction produced no directory." >&2
    exit 1
}
echo "  Extracted: $(basename "${EXTRACTED}")"

# ---------------------------------------------------------------------------
# Build Ninja
# Ninja has a self-contained bootstrap build — no CMake needed.
# ---------------------------------------------------------------------------
echo ""
echo "[Step 2/2] Building Ninja (bootstrap)…"
echo "           This takes ~30 seconds."
echo ""

cd "${EXTRACTED}"

if [[ "${OS}" == "windows" ]]; then
    # Windows bootstrap uses MSVC via the configure.py script
    python3 configure.py --bootstrap 2>&1 | tail -5
    BUILT_BIN="${EXTRACTED}/ninja.exe"
else
    # Linux/macOS bootstrap
    python3 configure.py --bootstrap 2>&1 | tail -5
    BUILT_BIN="${EXTRACTED}/ninja"
fi

cd "${SUBMODULE_ROOT}"

[[ -x "${BUILT_BIN}" ]] || {
    echo "ERROR: Ninja binary not found at ${BUILT_BIN} after build." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
mkdir -p "${BIN_DIR}"
cp "${BUILT_BIN}" "${OUTPUT_BIN}"
chmod +x "${OUTPUT_BIN}"

# Clean up build directory
rm -rf "${BUILD_DIR}"

echo ""
NINJA_VER_OUT="$("${OUTPUT_BIN}" --version 2>/dev/null || echo "unknown")"
echo "=================================================================="
echo "  Ninja ${NINJA_VER_OUT} built successfully ✓"
echo "=================================================================="
echo ""
echo "  Binary : ${OUTPUT_BIN}"
echo ""
