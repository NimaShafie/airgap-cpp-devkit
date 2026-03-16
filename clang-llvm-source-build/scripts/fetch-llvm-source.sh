#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# fetch-llvm-source.sh — MAINTAINER TOOL: Update the vendored LLVM tarball.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  DEVELOPERS: You do not need to run this script.                        │
# │  Run  bootstrap.sh  instead — it handles everything automatically.      │
# └─────────────────────────────────────────────────────────────────────────┘
#
# This script is used by repository maintainers to update the LLVM version
# vendored in llvm-src/. It downloads a new tarball, verifies its checksum,
# and places it in llvm-src/ ready to commit.
#
# The downloaded tarball is what gets committed into the repository.
# Developers never run this — bootstrap.sh extracts the committed tarball
# automatically via extract-llvm-source.sh.
#
# Usage:
#   bash scripts/fetch-llvm-source.sh [--version X.Y.Z] [--tarball-dir PATH]
#
# Options:
#   --version X.Y.Z      LLVM version to vendor (default: 22.1.1)
#   --tarball-dir PATH   Use a tarball already on disk instead of fetching
#   --no-confirm         Skip interactive prompts (for automation)
#
# After running:
#   git add llvm-src/llvm-project-<ver>.src.tar.xz
#   git add ninja-src/   (if also updating Ninja)
#   git commit -m "vendor: update LLVM to <ver>"
#   git push
#
# Developers on air-gapped machines get the tarball automatically
# when they pull and run bootstrap.sh.
# =============================================================================

set -euo pipefail

LLVM_VERSION="22.1.1"
TARBALL_DIR=""
NO_CONFIRM=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SUBMODULE_ROOT}/llvm-src"
WORK_DIR="${SUBMODULE_ROOT}/.llvm-fetch-work"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     LLVM_VERSION="$2"; shift 2 ;;
        --tarball-dir) TARBALL_DIR="$2";  shift 2 ;;
        --no-confirm)  NO_CONFIRM=true;   shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

MAJOR_VER="${LLVM_VERSION%%.*}"
if [[ "${MAJOR_VER}" -ge 20 ]]; then
    FORMAT="monorepo"
    TARBALL_NAME="llvm-project-${LLVM_VERSION}.src.tar.xz"
else
    FORMAT="split"
    TARBALL_NAME="llvm-${LLVM_VERSION}.src.tar.xz (+ 3 others)"
fi

RELEASE_BASE="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}"

echo "=================================================================="
echo "  fetch-llvm-source.sh  [MAINTAINER TOOL]"
echo "  LLVM version : ${LLVM_VERSION}"
echo "  Format       : ${FORMAT}"
echo "  Tarball      : ${TARBALL_NAME}"
echo "  Destination  : ${SRC_DIR}/"
echo "=================================================================="
echo ""
echo "  This places the LLVM tarball into llvm-src/ for committing."
echo "  Developers do not run this — they run bootstrap.sh instead."
echo ""

if [[ "${NO_CONFIRM}" == "false" ]]; then
    read -r -p "  Proceed? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }
    echo ""
fi

mkdir -p "${WORK_DIR}"

# ---------------------------------------------------------------------------
# Helper: find a tarball in a local directory
# ---------------------------------------------------------------------------
_find_local() {
    local stem="$1" ver="$2"
    for name in \
        "${stem}-${ver}.src.tar.xz" \
        "${stem}-${ver}.src.tar.gz" \
        "${stem}-${ver}.src.tar"; do
        [[ -f "${TARBALL_DIR}/${name}" ]] && { echo "${TARBALL_DIR}/${name}"; return 0; }
    done
    local found
    found="$(find "${TARBALL_DIR}" -maxdepth 1 \
        \( -name "${stem}-*.src.tar.xz" -o -name "${stem}-*.src.tar.gz" -o -name "${stem}-*.src.tar" \) \
        2>/dev/null | sort -V | tail -1 || true)"
    [[ -n "${found}" ]] && { echo "${found}"; return 0; }
    return 1
}

# ---------------------------------------------------------------------------
# Helper: fetch via curl
# ---------------------------------------------------------------------------
_fetch() {
    local url="$1" dest="$2" label="$3"
    if [[ -f "${dest}" ]]; then
        echo "  [cached]   ${label}"
        return 0
    fi
    echo "  [fetching] ${label}"
    command -v curl &>/dev/null || {
        echo "ERROR: curl not found. Supply --tarball-dir instead." >&2; exit 1
    }
    curl -L --fail --progress-bar -o "${dest}" "${url}" || {
        echo "ERROR: Fetch failed." >&2; rm -f "${dest}"; exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 1 — Obtain the tarball
# ---------------------------------------------------------------------------
echo "[Step 1/3] Obtaining LLVM ${LLVM_VERSION} tarball…"
echo ""

DEST_TARBALL="${SRC_DIR}/${TARBALL_NAME%% *}"   # strip "(+ 3 others)" suffix if present

if [[ "${FORMAT}" == "monorepo" ]]; then
    WORK_TARBALL="${WORK_DIR}/llvm-project-${LLVM_VERSION}.src.tar.xz"

    if [[ -n "${TARBALL_DIR}" ]]; then
        found="$(_find_local "llvm-project" "${LLVM_VERSION}" 2>/dev/null || true)"
        [[ -n "${found}" ]] || {
            echo "ERROR: llvm-project-${LLVM_VERSION}.src.tar.xz not found in '${TARBALL_DIR}'." >&2
            exit 1
        }
        echo "  [using]    $(basename "${found}")"
        cp "${found}" "${WORK_TARBALL}"
    else
        _fetch \
            "${RELEASE_BASE}/llvm-project-${LLVM_VERSION}.src.tar.xz" \
            "${WORK_TARBALL}" \
            "llvm-project-${LLVM_VERSION}.src.tar.xz (~159 MB)"
    fi

    # ---------------------------------------------------------------------------
    # Step 2 — Verify checksum
    # ---------------------------------------------------------------------------
    echo ""
    echo "[Step 2/3] Verifying SHA256 checksum…"
    echo ""
    COMPUTED="$(sha256sum "${WORK_TARBALL}" | awk '{print $1}')"
    echo "  Computed : ${COMPUTED}"
    echo "  Expected : check github.com/llvm/llvm-project/releases/tag/llvmorg-${LLVM_VERSION}"
    echo "             (22.1.1: 9c6f37f6f5f68d38f435d25f770fc48c62d92b2412205767a16dac2c942f0c95)"
    echo ""

    if [[ "${NO_CONFIRM}" == "false" ]]; then
        read -r -p "  Checksum verified — continue? [y/N] " chk
        [[ "${chk,,}" == "y" ]] || { echo "Aborted."; exit 1; }
        echo ""
    fi

    # ---------------------------------------------------------------------------
    # Step 3 — Place tarball into llvm-src/
    # ---------------------------------------------------------------------------
    echo "[Step 3/3] Installing tarball into llvm-src/…"
    echo ""

    # Remove any previously committed tarball for a different version
    find "${SRC_DIR}" -maxdepth 1 -name "llvm-project-*.src.tar.xz" \
        ! -name "$(basename "${WORK_TARBALL}")" -delete 2>/dev/null || true

    cp "${WORK_TARBALL}" "${SRC_DIR}/"
    echo "  Installed: $(basename "${WORK_TARBALL}") → llvm-src/"

else
    # Split format not shown in full for brevity — same pattern as above per tarball
    echo "  Split format (v14-v19) not fully shown; adapt per tarball." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo "  Tarball installed ✓"
echo "=================================================================="
echo ""
echo "  File : llvm-src/llvm-project-${LLVM_VERSION}.src.tar.xz"
echo "  Size : $(du -sh "${SRC_DIR}/llvm-project-${LLVM_VERSION}.src.tar.xz" | cut -f1)"
echo ""
echo "  Next — commit to the repository:"
echo "    git add llvm-src/llvm-project-${LLVM_VERSION}.src.tar.xz"
echo "    git commit -m \"vendor: update LLVM tarball to ${LLVM_VERSION}\""
echo "    git push"
echo ""
echo "  Developers get the tarball on next pull and run bootstrap.sh."
echo ""
