#!/usr/bin/env bash
# =============================================================================
# extract-llvm-source.sh — Extract the vendored LLVM tarball in llvm-src/
#                           into the source tree needed to build clang-format.
#
# Called automatically by bootstrap.sh and build-clang-format.sh.
#
# WINDOWS NOTES:
#   - Run from Git Bash (MINGW64).
#   - tar symlink errors are suppressed (harmless, test dirs are stripped).
#   - Do not run with File Explorer or another terminal open in llvm-src/.
#
# Usage:  bash scripts/extract-llvm-source.sh [--force]
# =============================================================================

set -uo pipefail   # no -e: tar exits non-zero on Windows for symlink errors

FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        -h|--help) echo "Usage: $0 [--force]"; exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SUBMODULE_ROOT}/llvm-src"
STAGE_DIR="${SUBMODULE_ROOT}/.llvm-extract-stage"
TARBALL=""
TARBALL_TEMP=""

# ---------------------------------------------------------------------------
# OS detection
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
# Cleanup trap — fires on any exit: success, error, or Ctrl-C
# ---------------------------------------------------------------------------
_cleanup() {
    local code=$?
    [[ -d "${STAGE_DIR}" ]]                               && rm -rf "${STAGE_DIR}" 2>/dev/null || true
    [[ -n "${TARBALL_TEMP:-}" && -f "${TARBALL_TEMP}" ]]  && rm -f  "${TARBALL_TEMP}" 2>/dev/null || true
    exit "${code}"
}
trap _cleanup EXIT

# ---------------------------------------------------------------------------
# Already extracted?
# ---------------------------------------------------------------------------
if [[ -f "${SRC_DIR}/llvm/CMakeLists.txt" && \
      -f "${SRC_DIR}/llvm/tools/clang/CMakeLists.txt" && \
      "${FORCE}" == "false" ]]; then
    echo "[extract-llvm] Source already extracted -- skipping. (--force to redo)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Locate tarball — single file or split .part-* files
# ---------------------------------------------------------------------------
for f in "${SRC_DIR}"/llvm-project-*.src.tar.xz \
          "${SRC_DIR}"/llvm-project-*.src.tar.gz; do
    [[ -f "${f}" ]] && { TARBALL="${f}"; break; }
done

if [[ -z "${TARBALL}" ]]; then
    FIRST_PART=""
    for f in "${SRC_DIR}"/llvm-project-*.src.tar.xz.part-aa; do
        [[ -f "${f}" ]] && { FIRST_PART="${f}"; break; }
    done
    if [[ -n "${FIRST_PART}" ]]; then
        BASE="${FIRST_PART%.part-aa}"
        PARTS=( $(ls "${BASE}".part-* 2>/dev/null | sort) )
        echo "  Found ${#PARTS[@]} split parts -- reassembling..."
        TARBALL_TEMP="${SRC_DIR}/.reassembled.tar.xz"
        cat "${PARTS[@]}" > "${TARBALL_TEMP}"
        TARBALL="${TARBALL_TEMP}"
        echo "  Reassembled: $(du -sh "${TARBALL}" | cut -f1)"
        echo ""
    fi
fi

[[ -n "${TARBALL}" ]] || {
    echo "ERROR: No LLVM tarball found in llvm-src/." >&2
    echo "  Expected: llvm-project-<ver>.src.tar.xz" >&2
    echo "       or:  llvm-project-<ver>.src.tar.xz.part-aa ..." >&2
    exit 1
}

# Extract version from the original filename (part-aa if split, tarball if single)
# .reassembled.tar.xz has no version in its name so we check the source
if [[ -n "${FIRST_PART:-}" ]]; then
    LLVM_VERSION="$(basename "${FIRST_PART}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")"
else
    LLVM_VERSION="$(basename "${TARBALL}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")"
fi
TARBALL_BYTES="$(du -sb "${TARBALL}" 2>/dev/null | cut -f1 || echo 167772160)"
TARBALL_MB=$(( TARBALL_BYTES / 1048576 ))

echo "=================================================================="
echo "  extract-llvm-source.sh"
echo "  LLVM     : ${LLVM_VERSION}"
echo "  Tarball  : $(basename "${TARBALL}") (${TARBALL_MB} MB)"
echo "  Platform : ${OS}"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Clear stale partial extraction from a previous run
# Preserves: tarballs, .part-* files, .gitignore, README.md
# ---------------------------------------------------------------------------
find "${SRC_DIR}" -mindepth 1 -maxdepth 1 \
    ! -name '*.tar.xz' ! -name '*.tar.gz' ! -name '*.part-*' \
    ! -name '.gitignore' ! -name 'README.md' ! -name '.reassembled.tar.xz' \
    -exec rm -rf {} + 2>/dev/null || true

# ============================================================================
# STEP 1 — Extract
# Uses GNU tar's built-in --checkpoint mechanism for progress reporting.
# --checkpoint=500 fires every 500 * 512-byte blocks = every ~250 KB.
# --checkpoint-action=dot prints a single character each time.
# No background jobs or polling needed — works reliably on Windows Git Bash.
# ============================================================================
echo "[1/3] Extracting tarball  (~${TARBALL_MB} MB compressed -> ~1 GB raw)"
echo ""

rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"

# Print a progress bar using checkpoint dots.
# Each dot = ~250 KB of tarball read. Total dots ~ TARBALL_MB * 4.
TOTAL_DOTS=$(( TARBALL_MB * 4 ))
BAR_WIDTH=50
DOT_COUNT=0

# Write dots to a temp file; a subshell reads and renders the bar.
DOT_PIPE="${STAGE_DIR}/.progress"
mkfifo "${DOT_PIPE}" 2>/dev/null || true

# Progress renderer — reads one char at a time from the pipe
_render_bar() {
    local pipe="$1" total="$2" width="$3" mb="$4"
    local n=0 filled empty bar
    while IFS= read -r -n1 c <"${pipe}"; do
        [[ -z "${c}" ]] && break
        n=$(( n + 1 ))
        filled=$(( n * width / (total + 1) ))
        [[ ${filled} -gt ${width} ]] && filled=${width}
        empty=$(( width - filled ))
        bar="$(printf '%*s' "${filled}" '' | tr ' ' '#')$(printf '%*s' "${empty}" '' | tr ' ' '-')"
        done_mb=$(( n * mb / (total + 1) ))
        printf "\r  [%s] %3d / %3d MB" "${bar}" "${done_mb}" "${mb}"
    done
    printf "\r  [%-${width}s] %3d / %3d MB  done\n" \
        "$(printf '%*s' "${width}" '' | tr ' ' '#')" "${mb}" "${mb}"
}

_render_bar "${DOT_PIPE}" "${TOTAL_DOTS}" "${BAR_WIDTH}" "${TARBALL_MB}" &
RENDER_PID=$!

tar -xf "${TARBALL}" -C "${STAGE_DIR}" \
    --checkpoint=500 \
    --checkpoint-action="ttyout=." \
    2>/dev/null >"${DOT_PIPE}" || true

echo "" > "${DOT_PIPE}" 2>/dev/null || true   # signal end
wait "${RENDER_PID}" 2>/dev/null || true
rm -f "${DOT_PIPE}"
echo ""

# ---------------------------------------------------------------------------
# Locate the extracted top-level directory
# ---------------------------------------------------------------------------
EXTRACTED=""
for d in "${STAGE_DIR}"/llvm-project-*.src "${STAGE_DIR}"/llvm-project-*; do
    [[ -d "${d}" ]] && { EXTRACTED="${d}"; break; }
done

[[ -n "${EXTRACTED}" ]] || {
    echo "ERROR: tar produced no output directory." >&2
    echo "  Contents of ${STAGE_DIR}:" >&2
    ls -la "${STAGE_DIR}" >&2 || true
    exit 1
}
echo "  Extracted: $(basename "${EXTRACTED}")"

# ============================================================================
# STEP 2 — Restructure for CMake
#
# CMake requires this layout:
#   llvm-src/llvm/               <- cmake -S target
#   llvm-src/llvm/tools/clang/   <- Clang nested inside LLVM
#   llvm-src/cmake/              <- build system modules
#   llvm-src/third-party/        <- build system support
#
# CRITICAL: Do NOT mkdir llvm/ before moving it.
# If llvm/ already exists when we run "mv src/llvm dst/llvm", mv moves
# src/llvm INTO dst/llvm creating dst/llvm/llvm/ — wrong nesting.
# Correct order: move llvm/ first (dst must not exist), then mkdir
# llvm/tools/, then move clang/ into that slot.
# ============================================================================
echo ""
echo "[2/3] Restructuring source layout"
echo ""

for component in llvm clang cmake third-party; do
    [[ -d "${EXTRACTED}/${component}" ]] || {
        echo "ERROR: '${component}/' missing from extracted tarball." >&2
        exit 1
    }
done

# Remove any stale destination dirs from a previous partial run
for stale in "${SRC_DIR}/llvm" "${SRC_DIR}/cmake" "${SRC_DIR}/third-party"; do
    if [[ -d "${stale}" ]]; then
        printf "  %-36s removing stale copy...\n" "$(basename "${stale}")/"
        rm -rf "${stale}" || {
            echo "ERROR: Cannot remove ${stale}" >&2
            echo "  Close any File Explorer or editor windows in llvm-src/ and retry." >&2
            exit 1
        }
    fi
done

# Move helper: count files, show label, move, confirm done.
# No du/disk scan — file count via find is much faster on Windows.
_move() {
    local src="$1" dst="$2" label="$3"
    local count
    count="$(find "${src}" -type f 2>/dev/null | wc -l | tr -d ' ')"
    printf "  %-36s %6s files  ->  moving..." "${label}" "${count}"
    mv "${src}" "${dst}"
    printf "\r  %-36s %6s files  ->  done      \n" "${label}" "${count}"
}

# Move llvm/ FIRST — destination must not exist yet (no mkdir beforehand)
_move "${EXTRACTED}/llvm"        "${SRC_DIR}/llvm"             "llvm/"

# NOW create tools/ inside the moved llvm/, then move clang into it
mkdir -p "${SRC_DIR}/llvm/tools"
_move "${EXTRACTED}/clang"       "${SRC_DIR}/llvm/tools/clang" "llvm/tools/clang/"
_move "${EXTRACTED}/cmake"       "${SRC_DIR}/cmake"            "cmake/"
_move "${EXTRACTED}/third-party" "${SRC_DIR}/third-party"      "third-party/"

rm -rf "${EXTRACTED}"

# ============================================================================
# STEP 3 — Strip test, benchmark, and docs subdirectories
#
# Strips ~1.5 GB of test infrastructure, reducing ~2 GB to ~600 MB.
# Uses -mindepth 1 (include immediate children) with -type d and -name
# matching only known strip targets. CMakeLists.txt is a FILE so -type d
# never touches it. We print a running deleted-dir count for progress.
#
# NOTE: do NOT strip docs/ at depth 1 under llvm/ — CMake references it.
# We strip docs/ only at depth >= 2 (nested docs inside lib/ etc. are safe).
# ============================================================================
echo ""
echo "[3/3] Stripping test and benchmark directories"
echo ""

# Strip using a list-then-delete approach so we can show live progress.
# 1. find writes matching dir paths to a temp file (fast, no deletion yet)
# 2. We print how many were found
# 3. xargs rm -rf deletes them in batches, printing a running count
_strip() {
    local root="$1" label="$2"
    local listfile="${STAGE_DIR}/.strip-list"

    printf "  %-36s scanning..." "${label}"

    # Collect all dirs to strip into a list file
    find "${root}" -mindepth 1 -depth -type d         \( -name test    -o -name tests              -o -name unittests -o -name unittest         -o -name benchmarks -o -name benchmark \)         2>/dev/null > "${listfile}" || true

    # docs/ only at depth >= 2 (protect top-level llvm/docs/)
    find "${root}" -mindepth 2 -depth -type d -name docs         2>/dev/null >> "${listfile}" || true

    local total
    total=$(wc -l < "${listfile}" | tr -d ' ')
    printf "
  %-36s found %s dirs to strip -- deleting..." "${label}" "${total}"

    if [[ "${total}" -gt 0 ]]; then
        # Delete in batches; each batch prints a dot so screen stays live
        local deleted=0
        while IFS= read -r dir; do
            [[ -d "${dir}" ]] && rm -rf "${dir}" 2>/dev/null || true
            deleted=$(( deleted + 1 ))
            # Print a progress update every 50 deletions
            if (( deleted % 50 == 0 )); then
                printf "
  %-36s deleted %s / %s dirs..." "${label}" "${deleted}" "${total}"
            fi
        done < "${listfile}"
    fi

    rm -f "${listfile}"
    printf "
  %-36s done (%s dirs stripped)          
" "${label}" "${total}"
}

before_mb="$(du -sm "${SRC_DIR}/llvm" 2>/dev/null | cut -f1)"
_strip "${SRC_DIR}/llvm"             "llvm/"
_strip "${SRC_DIR}/llvm/tools/clang" "llvm/tools/clang/"
after_mb="$(du -sm "${SRC_DIR}/llvm" 2>/dev/null | cut -f1)"

echo ""
echo "  llvm/ tree: ${before_mb} MB -> ${after_mb} MB"

# ============================================================================
# Verify
# ============================================================================
echo ""
echo "  Verifying layout..."
VERIFY_OK=true
for check in \
    "${SRC_DIR}/llvm/CMakeLists.txt" \
    "${SRC_DIR}/llvm/tools/clang/CMakeLists.txt" \
    "${SRC_DIR}/cmake" \
    "${SRC_DIR}/third-party"; do
    if [[ -e "${check}" ]]; then
        printf "  [OK]  %s\n" "${check#${SRC_DIR}/}"
    else
        printf "  [!!]  MISSING: %s\n" "${check#${SRC_DIR}/}" >&2
        VERIFY_OK=false
    fi
done

[[ "${VERIFY_OK}" == "true" ]] || {
    echo ""
    echo "ERROR: Layout verification failed." >&2
    exit 1
}

printf "LLVM_VERSION=%s\nEXTRACTED=%s\nSTRIPPED=true\n" \
    "${LLVM_VERSION}" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    > "${SRC_DIR}/SOURCE_INFO.txt"

echo ""
echo "=================================================================="
echo "  Extraction complete  --  LLVM ${LLVM_VERSION} ready to build"
echo "=================================================================="
echo ""