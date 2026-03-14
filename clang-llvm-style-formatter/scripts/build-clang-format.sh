#!/usr/bin/env bash
# =============================================================================
# build-clang-format.sh — Build clang-format from the vendored LLVM source
#                          in llvm-src/ and install it into bin/<platform>/.
#
# This script is called automatically by bootstrap.sh when clang-format is
# not found. Developers can also run it directly.
#
# What it does:
#   1. Extracts llvm-src/ from the committed tarball if not already done.
#   2. Builds Ninja from ninja-src/ if not on PATH and not already built.
#   3. Configures and builds clang-format via CMake + Ninja (or make).
#   4. Installs the binary to bin/windows/ or bin/linux/.
#
# Prerequisites (must already be installed on the machine):
#   Windows : Visual Studio 2017/2019/2022 with C++ workload, CMake 3.14+
#             Run from an x64 Native Tools Command Prompt for VS.
#   RHEL 8  : GCC 8+ (gcc-c++), CMake 3.14+, Python 3.6+
#
# Ninja is vendored in ninja-src/ and built automatically if not found.
# No separate Ninja installation is required.
#
# The compiled binary is installed to:
#   bin/windows/clang-format.exe   (Windows)
#   bin/linux/clang-format          (Linux)
#
# The pre-commit hook and find-tools.sh discover these paths automatically.
#
# Usage:
#   bash scripts/build-clang-format.sh [--jobs N] [--rebuild]
#
# Options:
#   --jobs N    Parallel compile jobs (default: all CPU cores)
#   --rebuild   Delete existing build directory and rebuild from scratch
# =============================================================================

set -euo pipefail

JOBS=""
REBUILD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs)    JOBS="$2";    shift 2 ;;
        --rebuild) REBUILD=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--jobs N] [--rebuild]"
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SUBMODULE_ROOT}/llvm-src"
BUILD_DIR="${SRC_DIR}/build"

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
        OUTPUT_BIN="${BIN_DIR}/clang-format.exe"
        ;;
    *)
        BIN_DIR="${SUBMODULE_ROOT}/bin/linux"
        OUTPUT_BIN="${BIN_DIR}/clang-format"
        ;;
esac

# ---------------------------------------------------------------------------
# Already built?
# ---------------------------------------------------------------------------
if [[ -x "${OUTPUT_BIN}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1)"
    echo "[build-clang-format] Already built: ${VER}"
    echo "                     Location: ${OUTPUT_BIN}"
    echo "                     Use --rebuild to force a rebuild."
    exit 0
fi

if [[ "${REBUILD}" == "true" && -d "${BUILD_DIR}" ]]; then
    echo "[build-clang-format] --rebuild: removing ${BUILD_DIR}…"
    rm -rf "${BUILD_DIR}"
fi

# ---------------------------------------------------------------------------
# Step 1 — Extract LLVM source if not already done
# ---------------------------------------------------------------------------
LLVM_CMAKE="${SRC_DIR}/llvm/CMakeLists.txt"
if [[ ! -f "${LLVM_CMAKE}" ]]; then
    echo "[build-clang-format] LLVM source not extracted — running extract-llvm-source.sh…"
    echo ""
    bash "${SCRIPT_DIR}/extract-llvm-source.sh"
    echo ""
fi

# Get the LLVM version for the banner
LLVM_VERSION="unknown"
[[ -f "${SRC_DIR}/SOURCE_INFO.txt" ]] \
    && LLVM_VERSION="$(grep '^LLVM_VERSION=' "${SRC_DIR}/SOURCE_INFO.txt" | cut -d= -f2)"

echo "=================================================================="
echo "  build-clang-format.sh"
echo "  LLVM version : ${LLVM_VERSION}"
echo "  Platform     : ${OS}"
echo "  Output       : ${OUTPUT_BIN}"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Step 2 — Locate or build Ninja
# ---------------------------------------------------------------------------
NINJA_BIN=""

# Check PATH first
if command -v ninja &>/dev/null; then
    NINJA_BIN="$(command -v ninja)"
    echo "  Ninja : ${NINJA_BIN} ($(ninja --version))"
fi

# Check vendored bin/
if [[ -z "${NINJA_BIN}" ]]; then
    for candidate in \
        "${SUBMODULE_ROOT}/bin/windows/ninja.exe" \
        "${SUBMODULE_ROOT}/bin/linux/ninja"; do
        if [[ -x "${candidate}" ]]; then
            NINJA_BIN="${candidate}"
            echo "  Ninja : ${NINJA_BIN} (vendored, $("${NINJA_BIN}" --version))"
            break
        fi
    done
fi

# Not found — build from ninja-src/
if [[ -z "${NINJA_BIN}" ]]; then
    NINJA_TARBALL=""
    for f in "${SUBMODULE_ROOT}/ninja-src"/ninja-*.tar.gz \
              "${SUBMODULE_ROOT}/ninja-src"/ninja-*.tar.xz; do
        [[ -f "${f}" ]] && { NINJA_TARBALL="${f}"; break; }
    done

    if [[ -n "${NINJA_TARBALL}" ]]; then
        echo "  Ninja not found — building from vendored source…"
        echo ""
        bash "${SCRIPT_DIR}/build-ninja.sh"
        echo ""

        # Pick up newly built binary
        for candidate in \
            "${SUBMODULE_ROOT}/bin/windows/ninja.exe" \
            "${SUBMODULE_ROOT}/bin/linux/ninja"; do
            if [[ -x "${candidate}" ]]; then
                NINJA_BIN="${candidate}"
                break
            fi
        done
    else
        echo "  Ninja not found and no ninja-src/ tarball present." >&2
        echo "  Falling back to make (slower)." >&2
    fi
fi

# ---------------------------------------------------------------------------
# Step 3 — Check for a C++ compiler and CMake
# ---------------------------------------------------------------------------
_require() {
    command -v "$1" &>/dev/null || {
        echo "" >&2
        echo "ERROR: '$1' ($2) is required but not found on PATH." >&2
        _prereq_help
        exit 1
    }
}

_prereq_help() {
    echo "" >&2
    echo "  Build prerequisites:" >&2
    case "${OS}" in
        windows)
            echo "    • Visual Studio 2017/2019/2022 with C++ workload" >&2
            echo "    • CMake 3.14+ (bundled with VS 2019+)" >&2
            echo "    • Run from: x64 Native Tools Command Prompt for VS" >&2
            ;;
        *)
            echo "    • GCC 8+   : sudo dnf install gcc-c++" >&2
            echo "    • CMake    : sudo dnf install cmake" >&2
            echo "    • Python 3 : pre-installed on RHEL 8" >&2
            ;;
    esac
    echo "" >&2
    echo "  See: ${SUBMODULE_ROOT}/docs/llvm-install-guide.md" >&2
}

_require cmake "CMake 3.14+"

if [[ "${OS}" != "windows" ]]; then
    _require g++ "GCC C++ compiler" 2>/dev/null \
    || _require c++ "C++ compiler"
fi

echo "  CMake : $(cmake --version | head -1)"

# Parallel jobs
if [[ -z "${JOBS}" ]]; then
    if command -v nproc &>/dev/null; then
        JOBS="$(nproc)"
    elif [[ "${OS}" == "windows" && -n "${NUMBER_OF_PROCESSORS:-}" ]]; then
        JOBS="${NUMBER_OF_PROCESSORS}"
    else
        JOBS="4"
    fi
fi
echo "  Jobs  : ${JOBS}"
echo ""

# ---------------------------------------------------------------------------
# Step 4 — CMake configure
# ---------------------------------------------------------------------------
echo "[Step 1/3] CMake configure…"
echo ""

mkdir -p "${BUILD_DIR}"

# Select generator
if [[ -n "${NINJA_BIN}" ]]; then
    CMAKE_GENERATOR="-G Ninja"
    BUILD_CMD=("${NINJA_BIN}" -C "${BUILD_DIR}" -j "${JOBS}" clang-format)
else
    CMAKE_GENERATOR=""
    BUILD_CMD=(make -C "${BUILD_DIR}" -j "${JOBS}" clang-format)
fi

CMAKE_SRC="${SRC_DIR}/llvm"

CMAKE_ARGS=(
    ${CMAKE_GENERATOR}
    -S "${CMAKE_SRC}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_ENABLE_PROJECTS="clang"
    -DLLVM_TARGETS_TO_BUILD="host"
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_BUILD_TOOLS=ON
    -DLLVM_ENABLE_ASSERTIONS=OFF
    -DCLANG_INCLUDE_TESTS=OFF
    -DCLANG_BUILD_TOOLS=ON
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
    -DCMAKE_INSTALL_PREFIX="${SRC_DIR}/install"
)

# Point CMake at the sibling cmake/ and third-party/ directories
if [[ -d "${SRC_DIR}/cmake" && -d "${SRC_DIR}/third-party" ]]; then
    CMAKE_ARGS+=(
        -DLLVM_COMMON_CMAKE_UTILS="${SRC_DIR}/cmake"
        -DLLVM_THIRD_PARTY_DIR="${SRC_DIR}/third-party"
    )
fi

# If we built a vendored Ninja, tell CMake where it is
if [[ -n "${NINJA_BIN}" ]]; then
    CMAKE_ARGS+=(-DCMAKE_MAKE_PROGRAM="${NINJA_BIN}")
fi

cmake "${CMAKE_ARGS[@]}"
echo ""

# ---------------------------------------------------------------------------
# Step 5 — Build
# ---------------------------------------------------------------------------
echo "[Step 2/3] Building clang-format (${JOBS} jobs)…"
echo "           Expected time: 30–60 minutes on first build."
echo ""

"${BUILD_CMD[@]}"
echo ""

# ---------------------------------------------------------------------------
# Step 6 — Install binary to bin/
# ---------------------------------------------------------------------------
echo "[Step 3/3] Installing…"

mkdir -p "${BIN_DIR}"

BUILT_BIN=""
for candidate in \
    "${BUILD_DIR}/bin/clang-format.exe" \
    "${BUILD_DIR}/bin/clang-format"; do
    [[ -f "${candidate}" ]] && { BUILT_BIN="${candidate}"; break; }
done

[[ -n "${BUILT_BIN}" ]] || {
    echo "ERROR: clang-format binary not found in ${BUILD_DIR}/bin/" >&2
    exit 1
}

cp "${BUILT_BIN}" "${OUTPUT_BIN}"
chmod +x "${OUTPUT_BIN}"

echo ""
VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1)"
echo "=================================================================="
echo "  Build complete ✓"
echo "=================================================================="
echo ""
echo "  Binary  : ${OUTPUT_BIN}"
echo "  Version : ${VER}"
echo ""
echo "  The pre-commit hook will use this binary automatically."
echo ""
echo "  To reclaim ~420 MB of build disk space:"
echo "    rm -rf ${BUILD_DIR}"
echo ""
