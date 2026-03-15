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
    # Run extract in a subshell with error handling disabled so that Windows
    # tar symlink failures (which are harmless) do not kill this script.
    bash "${SCRIPT_DIR}/extract-llvm-source.sh" || {
        # tar on Windows exits non-zero for symlink errors in test/ dirs.
        # Check whether extraction actually succeeded by looking for CMakeLists.txt.
        if [[ ! -f "${LLVM_CMAKE}" ]]; then
            echo "ERROR: extract-llvm-source.sh failed — CMakeLists.txt not found." >&2
            echo "       Check the output above for actual errors." >&2
            exit 1
        fi
        echo "  (Extraction completed with non-fatal warnings — continuing)"
    }
    echo ""
fi

# Get the LLVM version for the banner
# Priority: SOURCE_INFO.txt (written by extract) -> part filename -> CMakeLists.txt
LLVM_VERSION=""
if [[ -f "${SRC_DIR}/SOURCE_INFO.txt" ]]; then
    LLVM_VERSION="$(grep '^LLVM_VERSION=' "${SRC_DIR}/SOURCE_INFO.txt" | cut -d= -f2)"
fi
if [[ -z "${LLVM_VERSION}" || "${LLVM_VERSION}" == "unknown" ]]; then
    # Try to read from committed part filename
    for f in "${SRC_DIR}"/llvm-project-*.src.tar.xz.part-aa               "${SRC_DIR}"/llvm-project-*.src.tar.xz; do
        [[ -f "${f}" ]] && {
            LLVM_VERSION="$(basename "${f}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
            break
        }
    done
fi
if [[ -z "${LLVM_VERSION}" || "${LLVM_VERSION}" == "unknown" ]]; then
    # Last resort: read from extracted CMakeLists.txt
    _cmake="${SRC_DIR}/llvm/CMakeLists.txt"
    if [[ -f "${_cmake}" ]]; then
        LLVM_VERSION="$(grep -oE 'LLVM_VERSION [0-9]+\.[0-9]+\.[0-9]+' "${_cmake}"             | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    fi
fi
[[ -z "${LLVM_VERSION}" ]] && LLVM_VERSION="unknown"

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

# ---------------------------------------------------------------------------
# On Windows: locate cl.exe (MSVC compiler)
#
# Git Bash does not set up the VS Developer environment, so cl.exe is
# not on PATH. We search standard VS installation paths and pass it to
# CMake explicitly. CC/CXX are always unset to prevent GCC interference.
# ---------------------------------------------------------------------------
CL_EXE=""
if [[ "${OS}" == "windows" ]]; then
    unset CC CXX 2>/dev/null || true

    # ------------------------------------------------------------------
    # Locate cl.exe using three methods in order of reliability:
    #
    # 1. vswhere.exe  — ships with every VS 2017+ install, handles all
    #                   editions: Community, Professional, Enterprise,
    #                   Build Tools, Preview, and Insider editions.
    #                   Use -prerelease to include Preview/Insider.
    #
    # 2. Filesystem scan — walks all directories under both Program Files
    #                   roots, finds every cl.exe at Hostx64/x64 depth,
    #                   and picks the newest MSVC toolchain by version.
    #                   Catches any layout vswhere misses.
    #
    # 3. PATH fallback — if running from a VS Developer Command Prompt,
    #                   cl.exe is already on PATH.
    # ------------------------------------------------------------------

    # Method 1: vswhere
    VSWHERE=""
    for vsp in         "/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"         "/c/Program Files/Microsoft Visual Studio/Installer/vswhere.exe"; do
        [[ -f "${vsp}" ]] && { VSWHERE="${vsp}"; break; }
    done

    if [[ -n "${VSWHERE}" ]]; then
        VS_INSTALL="$("${VSWHERE}" -latest -prerelease -products '*'             -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64             -property installationPath 2>/dev/null | tr -d '
')"
        if [[ -n "${VS_INSTALL}" ]]; then
            VS_BASH="$(cygpath -u "${VS_INSTALL}" 2>/dev/null ||                 printf '%s' "${VS_INSTALL}" | sed 's|\\|/|g; s|^C:|/c|i; s|^D:|/d|i')"
            MSVC_ROOT="${VS_BASH}/VC/Tools/MSVC"
            if [[ -d "${MSVC_ROOT}" ]]; then
                MSVC_VER="$(ls -1 "${MSVC_ROOT}" 2>/dev/null | sort -V | tail -1)"
                _cl="${MSVC_ROOT}/${MSVC_VER}/bin/Hostx64/x64/cl.exe"
                [[ -f "${_cl}" ]] && CL_EXE="${_cl}"
            fi
        fi
    fi

    # Method 2: filesystem scan (handles any edition / install layout)
    if [[ -z "${CL_EXE}" ]]; then
        [[ -n "${VSWHERE}" ]] && echo "  vswhere found no MSVC -- scanning filesystem..."
        while IFS= read -r _cl; do
            [[ -f "${_cl}" ]] && { CL_EXE="${_cl}"; break; }
        done < <(
            find                 "/c/Program Files/Microsoft Visual Studio"                 "/c/Program Files (x86)/Microsoft Visual Studio"                 -name "cl.exe" -path "*/Hostx64/x64/cl.exe"                 2>/dev/null | sort -t/ -k9 -V -r
        )
    fi

    # Method 3: PATH fallback (VS Developer Command Prompt)
    if [[ -z "${CL_EXE}" ]] && command -v cl.exe &>/dev/null; then
        CL_EXE="$(command -v cl.exe)"
    fi

    if [[ -n "${CL_EXE}" ]]; then
        echo "  MSVC  : ${CL_EXE}"

        # Run vcvarsall.bat to set up the full MSVC environment:
        # Windows SDK paths, LIB, INCLUDE, PATH for link.exe, rc.exe, mt.exe.
        # Without this, the linker cannot find kernel32.lib and other SDK libs.
        # We capture the env vars it sets and apply them to the current shell.
        # Derive the VS install root from the CL_EXE path.
        # CL_EXE is always at: <VS_ROOT>/VC/Tools/MSVC/<ver>/bin/Hostx64/x64/cl.exe
        # vcvarsall.bat is at: <VS_ROOT>/VC/Auxiliary/Build/vcvarsall.bat
        # So we walk up 6 levels from cl.exe to reach <VS_ROOT>/VC, then
        # go sideways into Auxiliary/Build/. We also search up to 10 levels
        # to handle any non-standard install layouts.
        VCVARSALL=""
        _dir="$(dirname "${CL_EXE}")"
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            _dir="$(dirname "${_dir}")"
            # Check both direct location and Auxiliary/Build/ subdirectory
            if [[ -f "${_dir}/vcvarsall.bat" ]]; then
                VCVARSALL="${_dir}/vcvarsall.bat"
                break
            fi
            if [[ -f "${_dir}/Auxiliary/Build/vcvarsall.bat" ]]; then
                VCVARSALL="${_dir}/Auxiliary/Build/vcvarsall.bat"
                break
            fi
        done

        # Fallback: search the entire VS install tree (handles any layout)
        if [[ -z "${VCVARSALL}" ]]; then
            VS_SEARCH_ROOT="/c/Program Files/Microsoft Visual Studio"
            VCVARSALL="$(find "${VS_SEARCH_ROOT}"                 -name "vcvarsall.bat" 2>/dev/null | sort -V | tail -1)"
        fi
        if [[ -z "${VCVARSALL}" ]]; then
            VS_SEARCH_ROOT="/c/Program Files (x86)/Microsoft Visual Studio"
            VCVARSALL="$(find "${VS_SEARCH_ROOT}"                 -name "vcvarsall.bat" 2>/dev/null | sort -V | tail -1)"
        fi

        if [[ -n "${VCVARSALL}" ]]; then
            VCVARSALL_WIN="$(cygpath -w "${VCVARSALL}" 2>/dev/null ||                 printf '%s' "${VCVARSALL}" | sed 's|/c/|C:\\|; s|/|\\|g')"
            echo "  vcvars: ${VCVARSALL_WIN}"
        else
            echo "  WARNING: vcvarsall.bat not found." >&2
            echo "  If build fails with LNK1104, run from a VS Developer Prompt." >&2
            VCVARSALL_WIN=""
        fi
    else
        echo "" >&2
        echo "ERROR: cl.exe (MSVC C++ compiler) not found." >&2
        echo "" >&2
        echo "  LLVM requires MSVC on Windows. Install Visual Studio" >&2
        echo "  2017/2019/2022 (any edition, including Preview/Insider)" >&2
        echo "  with the 'Desktop development with C++' workload." >&2
        echo "" >&2
        echo "  Alternatively, run bootstrap from a VS Developer" >&2
        echo "  Command Prompt where cl.exe is already on PATH." >&2
        echo "" >&2
        echo "  See: ${SUBMODULE_ROOT}/docs/llvm-install-guide.md" >&2
        exit 1
    fi
fi

# Select CMake generator
if [[ "${OS}" == "windows" ]]; then
    if [[ -n "${NINJA_BIN}" ]]; then
        CMAKE_GENERATOR="-G Ninja"
        BUILD_CMD=("${NINJA_BIN}" -C "${BUILD_DIR}" -j "${JOBS}" clang-format)
    else
        CMAKE_GENERATOR="-G NMake Makefiles"
        BUILD_CMD=(cmake --build "${BUILD_DIR}" --target clang-format --config Release)
    fi
else
    if [[ -n "${NINJA_BIN}" ]]; then
        CMAKE_GENERATOR="-G Ninja"
        BUILD_CMD=("${NINJA_BIN}" -C "${BUILD_DIR}" -j "${JOBS}" clang-format)
    else
        CMAKE_GENERATOR=""
        BUILD_CMD=(make -C "${BUILD_DIR}" -j "${JOBS}" clang-format)
    fi
fi

CMAKE_SRC="${SRC_DIR}/llvm"

CMAKE_ARGS=(
    ${CMAKE_GENERATOR}
    -S "${CMAKE_SRC}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE=Release
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

# On Windows, explicitly set the compiler paths so CMake doesn't search PATH
if [[ -n "${CL_EXE:-}" ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_C_COMPILER="${CL_EXE}"
        -DCMAKE_CXX_COMPILER="${CL_EXE}"
    )
fi

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

# On Windows with vcvarsall: write a .bat that initializes the VS
# environment then runs cmake. This is the only reliable way to get
# LIB/INCLUDE/PATH set correctly — env var import into bash is fragile.
if [[ "${OS}" == "windows" ]]; then
    # Set up MSVC environment directly without relying on vcvarsall.
    # vcvarsall internally calls 'exit' (not 'exit /b') which kills any
    # cmd.exe session it runs in before our commands can execute.
    #
    # Instead we locate the Windows SDK and set LIB/INCLUDE/PATH ourselves.

    MSVC_ROOT="$(dirname "$(dirname "$(dirname "$(dirname "${CL_EXE}")")")")"
    MSVC_VER="$(basename "$(dirname "$(dirname "${CL_EXE}")")")"

    # Find Windows SDK root
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

    # Find newest SDK version
    WINSDK_VER="$(ls -1 "${WINSDK_ROOT}/lib" 2>/dev/null | sort -V | tail -1)"
    echo "  WinSDK: ${WINSDK_ROOT} (${WINSDK_VER})"

    # Convert all paths to Windows format for LIB/INCLUDE
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

    # Add MSVC and SDK bin dirs to PATH so link.exe, rc.exe etc. are found
    MSVC_BIN="${MSVC_ROOT}/bin/Hostx64/x64"
    SDK_BIN="${WINSDK_ROOT}/bin/${WINSDK_VER}/x64"
    export PATH="${MSVC_BIN}:${SDK_BIN}:${PATH}"

    echo "  LIB   : ${LIB}"
    echo ""
    cmake "${CMAKE_ARGS[@]}"
else
    cmake "${CMAKE_ARGS[@]}"
fi
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

# ---------------------------------------------------------------------------
# Smoke test — verify the build works end-to-end
# ---------------------------------------------------------------------------
SMOKE_SCRIPT="${SCRIPT_DIR}/smoke-test.sh"
if [[ -x "${SMOKE_SCRIPT}" ]]; then
    echo "Running smoke test..."
    echo ""
    bash "${SMOKE_SCRIPT}" || {
        echo "" >&2
        echo "WARNING: Smoke test reported failures." >&2
        echo "         Binary was built but check output above." >&2
    }
fi