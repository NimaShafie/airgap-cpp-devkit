#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# build-clang-tidy.sh — Build clang-tidy from the vendored LLVM source
#                        in llvm-src/ and install it into bin/<platform>/.
#
# This script is called automatically by bootstrap.sh when clang-tidy is
# not found. Developers can also run it directly.
#
# What it does:
#   1. Verifies LLVM source is extracted in llvm-src/ (run extract-llvm-source.sh
#      or bootstrap.sh first if not).
#   2. Reuses an existing CMake build directory from a prior clang-format build
#      if present — clang-tidy is an incremental target on the same tree.
#   3. Configures CMake with clang-tools-extra enabled (adds clang-tidy target).
#   4. Builds the clang-tidy target via CMake + Ninja (or NMake on Windows).
#   5. Installs the binary to bin/windows/ or bin/linux/.
#
# Prerequisites (must already be installed on the machine):
#   Windows : Visual Studio 2017/2019/2022/Insiders with C++ workload, CMake 3.14+
#             Run from Git Bash — VS environment is set up automatically.
#   RHEL 8  : GCC 8+ (gcc-c++), CMake 3.14+, Python 3.6+
#
# Note: clang-tidy requires building clang-tools-extra in addition to clang.
# This means the first build takes significantly longer than clang-format alone
# (~60-120 minutes on Windows, ~30-60 minutes on Linux).
# If clang-format was already built, the second build is incremental and faster.
#
# Usage:
#   bash scripts/build-clang-tidy.sh [--jobs N] [--rebuild]
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
REPO_ROOT="$(cd "${SUBMODULE_ROOT}/../.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/clang"
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
        OUTPUT_BIN="${BIN_DIR}/clang-tidy.exe"
        ;;
    *)
        BIN_DIR="${SUBMODULE_ROOT}/bin/linux"
        OUTPUT_BIN="${BIN_DIR}/clang-tidy"
        ;;
esac

# ---------------------------------------------------------------------------
# Already built?
# ---------------------------------------------------------------------------
if [[ -x "${OUTPUT_BIN}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1)"
    echo "[build-clang-tidy] Already built: ${VER}"
    echo "                   Location: ${OUTPUT_BIN}"
    echo "                   Use --rebuild to force a rebuild."
    exit 0
fi

if [[ "${REBUILD}" == "true" && -d "${BUILD_DIR}" ]]; then
    echo "[build-clang-tidy] --rebuild: removing ${BUILD_DIR}…"
    rm -rf "${BUILD_DIR}"
fi

# ---------------------------------------------------------------------------
# Verify LLVM source is extracted
# ---------------------------------------------------------------------------
LLVM_CMAKE="${SRC_DIR}/llvm/CMakeLists.txt"
if [[ ! -f "${LLVM_CMAKE}" ]]; then
    echo "ERROR: LLVM source not found at ${SRC_DIR}/llvm/CMakeLists.txt" >&2
    echo "" >&2
    echo "  Run bootstrap.sh first to extract the vendored source:" >&2
    echo "    bash ${SUBMODULE_ROOT}/bootstrap.sh" >&2
    echo "" >&2
    echo "  Or extract manually:" >&2
    echo "    bash scripts/extract-llvm-source.sh" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify clang-tools-extra source is present
# ---------------------------------------------------------------------------
TIDY_CMAKE="${SRC_DIR}/clang-tools-extra/CMakeLists.txt"
if [[ ! -f "${TIDY_CMAKE}" ]]; then
    echo "ERROR: clang-tools-extra source not found at ${SRC_DIR}/clang-tools-extra/" >&2
    echo "" >&2
    echo "  clang-tidy requires clang-tools-extra to be extracted alongside" >&2
    echo "  the main LLVM source. Re-run extract-llvm-source.sh:" >&2
    echo "    bash scripts/extract-llvm-source.sh" >&2
    exit 1
fi

# Get LLVM version for the banner
LLVM_VERSION=""
if [[ -f "${SRC_DIR}/SOURCE_INFO.txt" ]]; then
    LLVM_VERSION="$(grep '^LLVM_VERSION=' "${SRC_DIR}/SOURCE_INFO.txt" | cut -d= -f2)"
fi
if [[ -z "${LLVM_VERSION}" || "${LLVM_VERSION}" == "unknown" ]]; then
    for f in "${SRC_DIR}"/llvm-project-*.src.tar.xz.part-aa \
              "${SRC_DIR}"/llvm-project-*.src.tar.xz; do
        [[ -f "${f}" ]] && {
            LLVM_VERSION="$(basename "${f}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
            break
        }
    done
fi
[[ -z "${LLVM_VERSION}" ]] && LLVM_VERSION="unknown"

echo "=================================================================="
echo "  build-clang-tidy.sh"
echo "  LLVM version : ${LLVM_VERSION}"
echo "  Platform     : ${OS}"
echo "  Output       : ${OUTPUT_BIN}"
echo "=================================================================="
echo ""
echo "  clang-tidy requires clang-tools-extra in addition to clang."
echo "  First build: ~60-120 min (Windows) / ~30-60 min (Linux)."
echo "  Incremental build (reusing prior clang-format build): faster."
echo ""

# ---------------------------------------------------------------------------
# Locate or build Ninja
# ---------------------------------------------------------------------------
NINJA_BIN=""

if command -v ninja &>/dev/null; then
    NINJA_BIN="$(command -v ninja)"
    echo "  Ninja : ${NINJA_BIN} ($(ninja --version))"
fi

if [[ -z "${NINJA_BIN}" ]]; then
    for candidate in \
        "${PREBUILT_DIR}/ninja.exe" \
        "${PREBUILT_DIR}/ninja-linux" \
        "${SUBMODULE_ROOT}/bin/windows/ninja.exe" \
        "${SUBMODULE_ROOT}/bin/linux/ninja"; do
        if [[ -x "${candidate}" ]]; then
            NINJA_BIN="${candidate}"
            echo "  Ninja : ${NINJA_BIN} (vendored, $("${NINJA_BIN}" --version))"
            break
        fi
    done
fi

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
        for candidate in \
            "${PREBUILT_DIR}/ninja.exe" \
            "${PREBUILT_DIR}/ninja-linux" \
            "${SUBMODULE_ROOT}/bin/windows/ninja.exe" \
            "${SUBMODULE_ROOT}/bin/linux/ninja"; do
            if [[ -x "${candidate}" ]]; then
                NINJA_BIN="${candidate}"
                break
            fi
        done
    else
        echo "  Ninja not found and no ninja-src/ tarball present." >&2
        echo "  Falling back to NMake/make (slower)." >&2
    fi
fi

# ---------------------------------------------------------------------------
# Check for CMake
# ---------------------------------------------------------------------------
_prereq_help() {
    echo "" >&2
    echo "  Build prerequisites:" >&2
    case "${OS}" in
        windows)
            echo "    • Visual Studio 2017/2019/2022/Insiders with C++ workload" >&2
            echo "      (tested: VS Insiders 18, MSVC toolchain 14.50.35717)" >&2
            echo "    • CMake 4.1.2+ (tested), minimum 3.14" >&2
            echo "    • Run from Git Bash — VS environment set up automatically" >&2
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

command -v cmake &>/dev/null || {
    echo "" >&2
    echo "ERROR: cmake not found on PATH." >&2
    _prereq_help
    exit 1
}

if [[ "${OS}" != "windows" ]]; then
    command -v g++ &>/dev/null || command -v c++ &>/dev/null || {
        echo "" >&2
        echo "ERROR: C++ compiler not found on PATH." >&2
        _prereq_help
        exit 1
    }
fi

echo "  CMake : $(cmake --version | head -1)"

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
# Windows: locate cl.exe and set up MSVC environment
# (identical logic to build-clang-format.sh)
# ---------------------------------------------------------------------------
CL_EXE=""
if [[ "${OS}" == "windows" ]]; then
    unset CC CXX 2>/dev/null || true

    # Method 1: vswhere
    VSWHERE=""
    for vsp in \
        "/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe" \
        "/c/Program Files/Microsoft Visual Studio/Installer/vswhere.exe"; do
        [[ -f "${vsp}" ]] && { VSWHERE="${vsp}"; break; }
    done

    if [[ -n "${VSWHERE}" ]]; then
        VS_INSTALL="$("${VSWHERE}" -latest -prerelease -products '*' \
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
            -property installationPath 2>/dev/null | tr -d '\r')"
        if [[ -n "${VS_INSTALL}" ]]; then
            VS_BASH="$(cygpath -u "${VS_INSTALL}" 2>/dev/null || \
                printf '%s' "${VS_INSTALL}" | sed 's|\\|/|g; s|^C:|/c|i; s|^D:|/d|i')"
            MSVC_ROOT="${VS_BASH}/VC/Tools/MSVC"
            if [[ -d "${MSVC_ROOT}" ]]; then
                MSVC_VER="$(ls -1 "${MSVC_ROOT}" 2>/dev/null | sort -V | tail -1)"
                _cl="${MSVC_ROOT}/${MSVC_VER}/bin/Hostx64/x64/cl.exe"
                [[ -f "${_cl}" ]] && CL_EXE="${_cl}"
            fi
        fi
    fi

    # Method 2: filesystem scan
    if [[ -z "${CL_EXE}" ]]; then
        [[ -n "${VSWHERE}" ]] && echo "  vswhere found no MSVC — scanning filesystem..."
        while IFS= read -r _cl; do
            [[ -f "${_cl}" ]] && { CL_EXE="${_cl}"; break; }
        done < <(
            find \
                "/c/Program Files/Microsoft Visual Studio" \
                "/c/Program Files (x86)/Microsoft Visual Studio" \
                -name "cl.exe" -path "*/Hostx64/x64/cl.exe" \
                2>/dev/null | sort -t/ -k9 -V -r
        )
    fi

    # Method 3: PATH fallback
    if [[ -z "${CL_EXE}" ]] && command -v cl.exe &>/dev/null; then
        CL_EXE="$(command -v cl.exe)"
    fi

    if [[ -n "${CL_EXE}" ]]; then
        echo "  MSVC  : ${CL_EXE}"

        # Set up MSVC + Windows SDK environment
        MSVC_ROOT="$(dirname "$(dirname "$(dirname "$(dirname "${CL_EXE}")")")")"

        WINSDK_ROOT=""
        for sdk_root in \
            "/c/Program Files (x86)/Windows Kits/10" \
            "/c/Program Files/Windows Kits/10"; do
            [[ -d "${sdk_root}/lib" ]] && { WINSDK_ROOT="${sdk_root}"; break; }
        done

        if [[ -z "${WINSDK_ROOT}" ]]; then
            echo "ERROR: Windows SDK not found." >&2
            echo "  Install the Windows 10/11 SDK via Visual Studio Installer." >&2
            exit 1
        fi

        WINSDK_VER="$(ls -1 "${WINSDK_ROOT}/lib" 2>/dev/null | sort -V | tail -1)"
        echo "  WinSDK: ${WINSDK_ROOT} (${WINSDK_VER})"

        _w() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1" | sed 's|/c/|C:\\|; s|/|\\|g'; }

        MSVC_LIB="$(_w "${MSVC_ROOT}/lib/x64")"
        MSVC_INC="$(_w "${MSVC_ROOT}/include")"
        SDK_LIB_UM="$(_w "${WINSDK_ROOT}/lib/${WINSDK_VER}/um/x64")"
        SDK_LIB_UCRT="$(_w "${WINSDK_ROOT}/lib/${WINSDK_VER}/ucrt/x64")"
        SDK_INC_SHARED="$(_w "${WINSDK_ROOT}/include/${WINSDK_VER}/shared")"
        SDK_INC_UM="$(_w "${WINSDK_ROOT}/include/${WINSDK_VER}/um")"
        SDK_INC_UCRT="$(_w "${WINSDK_ROOT}/include/${WINSDK_VER}/ucrt")"
        SDK_INC_WINRT="$(_w "${WINSDK_ROOT}/include/${WINSDK_VER}/winrt")"

        export LIB="${MSVC_LIB};${SDK_LIB_UM};${SDK_LIB_UCRT}"
        export INCLUDE="${MSVC_INC};${SDK_INC_SHARED};${SDK_INC_UM};${SDK_INC_UCRT};${SDK_INC_WINRT}"

        MSVC_BIN="${MSVC_ROOT}/bin/Hostx64/x64"
        SDK_BIN="${WINSDK_ROOT}/bin/${WINSDK_VER}/x64"
        export PATH="${MSVC_BIN}:${SDK_BIN}:${PATH}"

        echo "  LIB   : ${LIB}"
        echo ""
    else
        echo "" >&2
        echo "ERROR: cl.exe (MSVC C++ compiler) not found." >&2
        echo "" >&2
        echo "  LLVM requires MSVC on Windows. Install Visual Studio" >&2
        echo "  2017/2019/2022 (any edition, including Preview/Insiders)" >&2
        echo "  with the 'Desktop development with C++' workload." >&2
        echo "" >&2
        echo "  Tested configuration:" >&2
        echo "    VS Insiders 18 | MSVC 14.50.35717 | CMake 4.1.2" >&2
        echo "" >&2
        echo "  See: ${SUBMODULE_ROOT}/docs/llvm-install-guide.md" >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# CMake configure
#
# Key difference from build-clang-format.sh:
#   -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra"
#
# If a build/ directory already exists from a clang-format build, CMake will
# reconfigure incrementally — clang-tools-extra gets added to the existing
# tree without recompiling already-built objects.
# ---------------------------------------------------------------------------
echo "[Step 1/3] CMake configure…"
echo ""

mkdir -p "${BUILD_DIR}"

if [[ "${OS}" == "windows" ]]; then
    if [[ -n "${NINJA_BIN}" ]]; then
        CMAKE_GENERATOR="-G Ninja"
        BUILD_CMD=("${NINJA_BIN}" -C "${BUILD_DIR}" -j "${JOBS}" clang-tidy)
    else
        CMAKE_GENERATOR="-G NMake Makefiles"
        BUILD_CMD=(cmake --build "${BUILD_DIR}" --target clang-tidy --config Release)
    fi
else
    if [[ -n "${NINJA_BIN}" ]]; then
        CMAKE_GENERATOR="-G Ninja"
        BUILD_CMD=("${NINJA_BIN}" -C "${BUILD_DIR}" -j "${JOBS}" clang-tidy)
    else
        CMAKE_GENERATOR=""
        BUILD_CMD=(make -C "${BUILD_DIR}" -j "${JOBS}" clang-tidy)
    fi
fi

CMAKE_SRC="${SRC_DIR}/llvm"

CMAKE_ARGS=(
    ${CMAKE_GENERATOR}
    -S "${CMAKE_SRC}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_TARGETS_TO_BUILD="host"
    -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra"
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

if [[ -n "${CL_EXE:-}" ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_C_COMPILER="${CL_EXE}"
        -DCMAKE_CXX_COMPILER="${CL_EXE}"
    )
fi
if [[ -d "${SRC_DIR}/cmake" && -d "${SRC_DIR}/third-party" ]]; then
    CMAKE_ARGS+=(
        -DLLVM_COMMON_CMAKE_UTILS="${SRC_DIR}/cmake"
        -DLLVM_THIRD_PARTY_DIR="${SRC_DIR}/third-party"
    )
fi

if [[ -n "${NINJA_BIN}" ]]; then
    CMAKE_ARGS+=(-DCMAKE_MAKE_PROGRAM="${NINJA_BIN}")
fi

cmake "${CMAKE_ARGS[@]}"
echo ""

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "[Step 2/3] Building clang-tidy (${JOBS} jobs)…"
echo "           Expected time: ~60-120 min (first build, Windows)."
echo "           Incremental (reusing clang-format build): faster."
echo ""

"${BUILD_CMD[@]}"
echo ""

# ---------------------------------------------------------------------------
# Install binary to bin/
# ---------------------------------------------------------------------------
echo "[Step 3/3] Installing…"

mkdir -p "${BIN_DIR}"

BUILT_BIN=""
for candidate in \
    "${BUILD_DIR}/bin/clang-tidy.exe" \
    "${BUILD_DIR}/bin/clang-tidy"; do
    [[ -f "${candidate}" ]] && { BUILT_BIN="${candidate}"; break; }
done

[[ -n "${BUILT_BIN}" ]] || {
    echo "ERROR: clang-tidy binary not found in ${BUILD_DIR}/bin/" >&2
    exit 1
}

cp "${BUILT_BIN}" "${OUTPUT_BIN}"
chmod +x "${OUTPUT_BIN}"

VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1)"

echo ""
echo "=================================================================="
echo "  Build complete ✓"
echo "=================================================================="
echo ""
echo "  Binary  : ${OUTPUT_BIN}"
echo "  Version : ${VER}"
echo ""
echo "  To reclaim build disk space (~2-4 GB):"
echo "    rm -rf ${BUILD_DIR}"
echo ""
echo "  Next — update manifest.json with the binary SHA256:"
echo "    sha256sum ${OUTPUT_BIN}"
echo ""