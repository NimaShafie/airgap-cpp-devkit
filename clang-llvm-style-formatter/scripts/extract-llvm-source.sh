#!/usr/bin/env bash
# =============================================================================
# extract-llvm-source.sh — Extract the vendored LLVM tarball in llvm-src/
#                           into the source tree needed to build clang-format.
#
# The tarball (llvm-project-22.1.1.src.tar.xz or similar) is committed
# directly in llvm-src/. This script extracts and restructures it in-place,
# then strips test directories to reduce disk usage.
#
# Called automatically by bootstrap.sh and build-clang-format.sh when the
# extracted source tree is not yet present. Developers can also run it
# directly.
#
# WINDOWS NOTES:
#   - Run from Git Bash (MINGW64).
#   - The tarball contains Linux symlinks inside test/ directories.
#     tar will attempt to create these and fail on Windows NTFS without
#     Developer Mode. The script suppresses these warnings — they are
#     harmless because the test/ directories are stripped immediately.
#   - Do not run while File Explorer or another terminal has llvm-src/ open.
#
# Usage:
#   bash scripts/extract-llvm-source.sh [--force]
#
# Options:
#   --force    Re-extract even if the source tree is already present.
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
SRC_DIR="${SUBMODULE_ROOT}/llvm-src"
WORK_DIR="${SRC_DIR}/.extract-work"

# ---------------------------------------------------------------------------
# Detect OS
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

# ---------------------------------------------------------------------------
# Check if extraction is already complete
# ---------------------------------------------------------------------------
LLVM_CMAKE="${SRC_DIR}/llvm/CMakeLists.txt"
CLANG_CMAKE="${SRC_DIR}/llvm/tools/clang/CMakeLists.txt"

if [[ -f "${LLVM_CMAKE}" && -f "${CLANG_CMAKE}" && "${FORCE}" == "false" ]]; then
    echo "[extract-llvm] Source already extracted — skipping."
    echo "               Use --force to re-extract."
    exit 0
fi

# ---------------------------------------------------------------------------
# Find the committed tarball
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Locate the tarball — either a single file or split parts (.part-aa, .part-ab…)
# The split-parts approach is used to stay under git hosting file size limits
# (GitHub: 100 MB, Bitbucket: configurable). Parts are reassembled on-the-fly
# into a temporary file that is deleted after extraction.
# ---------------------------------------------------------------------------
TARBALL=""
TARBALL_TEMP=""   # set if we reassembled from parts

# 1. Single-file tarball (preferred, used on servers with high limits)
for f in "${SRC_DIR}"/llvm-project-*.src.tar.xz \
          "${SRC_DIR}"/llvm-project-*.src.tar.gz; do
    [[ -f "${f}" ]] && { TARBALL="${f}"; break; }
done

# 2. Split parts — llvm-project-<ver>.src.tar.xz.part-aa, .part-ab, ...
if [[ -z "${TARBALL}" ]]; then
    FIRST_PART=""
    for f in "${SRC_DIR}"/llvm-project-*.src.tar.xz.part-aa; do
        [[ -f "${f}" ]] && { FIRST_PART="${f}"; break; }
    done

    if [[ -n "${FIRST_PART}" ]]; then
        # Derive the base name and find all parts in order
        BASE="${FIRST_PART%.part-aa}"
        PARTS=( $(ls "${BASE}".part-* 2>/dev/null | sort) )
        NUM_PARTS="${#PARTS[@]}"

        echo "  Found ${NUM_PARTS} split parts — reassembling tarball…"
        echo "  Parts: $(basename "${BASE}").part-*"
        echo ""

        TARBALL_TEMP="${SRC_DIR}/.reassembled.tar.xz"
        cat "${PARTS[@]}" > "${TARBALL_TEMP}"
        TARBALL="${TARBALL_TEMP}"
        echo "  Reassembled: $(du -sh "${TARBALL}" | cut -f1)"
    fi
fi

if [[ -z "${TARBALL}" ]]; then
    echo "" >&2
    echo "ERROR: No LLVM tarball found in llvm-src/." >&2
    echo "" >&2
    echo "  Expected either:" >&2
    echo "    llvm-src/llvm-project-<version>.src.tar.xz" >&2
    echo "  or split parts:" >&2
    echo "    llvm-src/llvm-project-<version>.src.tar.xz.part-aa" >&2
    echo "    llvm-src/llvm-project-<version>.src.tar.xz.part-ab  ..." >&2
    echo "" >&2
    echo "  These files should be committed in the repository." >&2
    echo "  If you are the maintainer, see scripts/fetch-llvm-source.sh" >&2
    exit 1
fi

LLVM_VERSION="$(basename "${TARBALL}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
TARBALL_SIZE="$(du -sh "${TARBALL}" 2>/dev/null | cut -f1)"

echo "=================================================================="
echo "  extract-llvm-source.sh"
echo "  Tarball  : $(basename "${TARBALL}") (${TARBALL_SIZE})"
echo "  Platform : ${OS}"
echo "  Into     : ${SRC_DIR}"
echo "=================================================================="
echo ""
echo "  Extracting ~160 MB → ~1 GB (before stripping)."
echo "  Stripping test directories reduces this to ~250 MB."
echo "  This takes 5–15 minutes on Windows, 2–5 minutes on Linux."
echo ""

# ---------------------------------------------------------------------------
# Clear any partial prior extraction (without removing the directory itself —
# Git Bash on Windows holds a handle on tracked directories)
# ---------------------------------------------------------------------------
if [[ "${FORCE}" == "true" ]]; then
    echo "  --force: clearing existing extracted files…"
fi

find "${SRC_DIR}" -mindepth 1 -maxdepth 1 \
    ! -name '*.tar.xz' \
    ! -name '*.tar.gz' \
    ! -name '.gitignore' \
    ! -name 'README.md' \
    ! -name '.extract-work' \
    -exec rm -rf {} + 2>/dev/null || {
    echo "" >&2
    echo "ERROR: Could not clear previous extraction." >&2
    echo "  Close any File Explorer windows, terminals, or editors" >&2
    echo "  that have llvm-src/ open, then rerun." >&2
    exit 1
}

mkdir -p "${WORK_DIR}"

# ---------------------------------------------------------------------------
# Extract tarball — suppressing Windows symlink errors
# The tarball contains Linux symlinks inside test/ directories that Windows
# NTFS cannot create. These fail silently here; test/ is removed in step 2.
# ---------------------------------------------------------------------------
echo "[Step 1/3] Extracting tarball…"
echo ""

if [[ "${OS}" == "windows" ]]; then
    # Filter symlink errors — they are all in test/ dirs we strip anyway
    tar -xf "${TARBALL}" -C "${SRC_DIR}" \
        --warning=no-failed-read 2>&1 \
        | grep -v "Cannot create symlink" \
        | grep -v "^tar: Exiting with failure" \
        | grep -v "^tar: Error" \
        || true
else
    tar -xf "${TARBALL}" -C "${SRC_DIR}"
fi

# The tarball extracts to: llvm-project-<ver>.src/
EXTRACTED=""
for d in "${SRC_DIR}"/llvm-project-*.src \
          "${SRC_DIR}"/llvm-project-*; do
    [[ -d "${d}" && "$(basename "${d}")" != ".extract-work" ]] \
        && { EXTRACTED="${d}"; break; }
done

[[ -n "${EXTRACTED}" ]] || {
    echo "ERROR: Tarball extraction produced no directory." >&2
    echo "  The tarball may be corrupt." >&2
    exit 1
}
echo "  Extracted: $(basename "${EXTRACTED}")"

# ---------------------------------------------------------------------------
# Restructure into CMake's expected layout:
#   llvm-src/llvm/               ← cmake -S points here
#   llvm-src/llvm/tools/clang/   ← Clang nested inside LLVM
#   llvm-src/cmake/              ← build system cmake modules
#   llvm-src/third-party/        ← build system support libs
# All other sub-projects (lld, lldb, mlir, bolt, flang, etc.) are discarded.
# ---------------------------------------------------------------------------
echo ""
echo "[Step 2/3] Restructuring for CMake layout…"

# Remove any leftover directories from a prior partial extraction.
# On Windows, mv fails with "Permission denied" if the destination
# directory already exists — removing it first avoids the collision.
for stale in "${SRC_DIR}/llvm" "${SRC_DIR}/cmake" "${SRC_DIR}/third-party"; do
    [[ -d "${stale}" ]] && rm -rf "${stale}"
done

mkdir -p "${SRC_DIR}/llvm/tools"

for component in llvm clang cmake third-party; do
    [[ -d "${EXTRACTED}/${component}" ]] || {
        echo "ERROR: '${component}/' not found in tarball." >&2
        exit 1
    }
done

mv "${EXTRACTED}/llvm"         "${SRC_DIR}/llvm"
mv "${EXTRACTED}/clang"        "${SRC_DIR}/llvm/tools/clang"
mv "${EXTRACTED}/cmake"        "${SRC_DIR}/cmake"
mv "${EXTRACTED}/third-party"  "${SRC_DIR}/third-party"

# Discard everything else (lld, lldb, mlir, bolt, flang, openmp, etc.)
rm -rf "${EXTRACTED}"
rm -rf "${WORK_DIR}"

echo "  Layout: llvm/  llvm/tools/clang/  cmake/  third-party/"
echo "  Raw size: $(du -sh "${SRC_DIR}" 2>/dev/null | cut -f1)"

# ---------------------------------------------------------------------------
# Strip test, benchmark, and doc directories to reduce disk footprint
# ---------------------------------------------------------------------------
echo ""
echo "[Step 3/3] Stripping test and benchmark directories…"

_strip() {
    local root="$1"
    for pattern in test tests unittests unittest benchmarks benchmark docs; do
        find "${root}" -depth -type d -name "${pattern}" \
            -exec rm -rf {} + 2>/dev/null || true
    done
}

before="$(du -sm "${SRC_DIR}" 2>/dev/null | cut -f1)"
_strip "${SRC_DIR}/llvm"
after="$(du -sm "${SRC_DIR}" 2>/dev/null | cut -f1)"
echo "  ${before} MB → ${after} MB"

# ---------------------------------------------------------------------------
# Verify the four required paths exist
# ---------------------------------------------------------------------------
echo ""
echo "  Verifying layout…"
VERIFY_OK=true
for check in \
    "${SRC_DIR}/llvm/CMakeLists.txt" \
    "${SRC_DIR}/llvm/tools/clang/CMakeLists.txt" \
    "${SRC_DIR}/cmake" \
    "${SRC_DIR}/third-party"; do
    if [[ -e "${check}" ]]; then
        echo "  ✓  ${check#${SRC_DIR}/}"
    else
        echo "  ✗  MISSING: ${check#${SRC_DIR}/}" >&2
        VERIFY_OK=false
    fi
done

[[ "${VERIFY_OK}" == "true" ]] || {
    echo "" >&2
    echo "ERROR: Layout verification failed." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Write SOURCE_INFO.txt
# ---------------------------------------------------------------------------
cat > "${SRC_DIR}/SOURCE_INFO.txt" << INFO
LLVM_VERSION=${LLVM_VERSION}
EXTRACTED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STRIPPED_TESTS=true
STRIPPED_BENCHMARKS=true
INFO

echo ""
echo "=================================================================="
echo "  Extraction complete ✓"
echo "=================================================================="
echo ""
echo "  LLVM ${LLVM_VERSION} source is ready to build."
echo "  Run: bash ${SCRIPT_DIR}/build-clang-format.sh"
echo ""
