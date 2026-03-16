#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# split-llvm-tarball.sh — MAINTAINER TOOL: Split the LLVM tarball into
#                          parts that fit under git hosting file size limits.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  DEVELOPERS: You do not need to run this script.                        │
# │  Run  bootstrap.sh  instead — it reassembles parts automatically.       │
# └─────────────────────────────────────────────────────────────────────────┘
#
# GitHub enforces a 100 MB per-file limit. Bitbucket Server/Data Center
# defaults to 250 MB but may be configured lower. This script splits the
# LLVM tarball into 95 MB chunks so it commits cleanly to either host.
#
# extract-llvm-source.sh detects and reassembles the parts transparently —
# developers see no difference between split and non-split tarballs.
#
# Usage:
#   bash scripts/split-llvm-tarball.sh [--chunk-size MB]
#
# Options:
#   --chunk-size MB   Size of each part in MB (default: 95)
#
# After running:
#   git rm   llvm-src/llvm-project-*.src.tar.xz       (the original)
#   git add  llvm-src/llvm-project-*.src.tar.xz.part-* (the parts)
#   git commit -m "vendor: split LLVM tarball into <100MB parts"
#   git push
# =============================================================================

set -euo pipefail

CHUNK_MB=95

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chunk-size) CHUNK_MB="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SUBMODULE_ROOT}/llvm-src"

# ---------------------------------------------------------------------------
# Find the tarball
# ---------------------------------------------------------------------------
TARBALL=""
for f in "${SRC_DIR}"/llvm-project-*.src.tar.xz; do
    [[ -f "${f}" ]] && { TARBALL="${f}"; break; }
done

if [[ -z "${TARBALL}" ]]; then
    echo "ERROR: No llvm-project-*.src.tar.xz found in llvm-src/." >&2
    echo "       Run fetch-llvm-source.sh first to add the tarball." >&2
    exit 1
fi

# Check if already split
FIRST_PART="${TARBALL}.part-aa"
if [[ -f "${FIRST_PART}" ]]; then
    echo "Parts already exist: $(ls "${TARBALL}".part-* | wc -l) parts"
    echo "Use: git rm ${TARBALL} and git add the .part-* files."
    exit 0
fi

TARBALL_SIZE="$(du -sm "${TARBALL}" | cut -f1)"
TARBALL_NAME="$(basename "${TARBALL}")"

echo "=================================================================="
echo "  split-llvm-tarball.sh  [MAINTAINER TOOL]"
echo "  Tarball    : ${TARBALL_NAME} (${TARBALL_SIZE} MB)"
echo "  Chunk size : ${CHUNK_MB} MB"
echo "  Output     : llvm-src/${TARBALL_NAME}.part-*"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Split
# ---------------------------------------------------------------------------
echo "  Splitting…"
split -b "${CHUNK_MB}m" "${TARBALL}" "${TARBALL}.part-"

PARTS=( $(ls "${TARBALL}".part-* | sort) )
NUM_PARTS="${#PARTS[@]}"

echo ""
echo "  Created ${NUM_PARTS} parts:"
for p in "${PARTS[@]}"; do
    echo "    $(basename "${p}")  ($(du -sh "${p}" | cut -f1))"
done

# ---------------------------------------------------------------------------
# Verify: reassemble and compare checksum
# ---------------------------------------------------------------------------
echo ""
echo "  Verifying: reassembling and comparing checksums…"

ORIG_SUM="$(sha256sum "${TARBALL}" | awk '{print $1}')"
REASSEMBLED="/tmp/llvm-split-verify-$$.tar.xz"
cat "${PARTS[@]}" > "${REASSEMBLED}"
REASSEMBLED_SUM="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
rm -f "${REASSEMBLED}"

if [[ "${ORIG_SUM}" == "${REASSEMBLED_SUM}" ]]; then
    echo "  ✓  Checksum verified — parts reassemble correctly."
else
    echo "  ✗  CHECKSUM MISMATCH — split failed." >&2
    rm -f "${PARTS[@]}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Instructions
# ---------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo "  Split complete ✓"
echo "=================================================================="
echo ""
echo "  Next — commit the parts and remove the original:"
echo ""
echo "    git rm llvm-src/${TARBALL_NAME}"
echo "    git add llvm-src/${TARBALL_NAME}.part-*"
echo "    git commit -m \"vendor: split LLVM tarball into ${NUM_PARTS} parts (<100MB each)\""
echo "    git push"
echo ""
echo "  extract-llvm-source.sh will reassemble the parts automatically"
echo "  when developers run bootstrap.sh — no action needed on their end."
echo ""
