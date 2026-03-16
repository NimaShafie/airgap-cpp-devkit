#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# fetch-wheels.sh — MAINTAINER TOOL: Download vendored Python wheels
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  DEVELOPERS: You do not need to run this script.                        │
# │  Run  bootstrap.sh  instead — it uses the already-committed wheels.     │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Downloads clang-format wheels for all supported platforms into
# python-packages/ so they can be committed to the repository.
#
# Run this on a machine with internet access when updating the clang-format
# version. Commit the resulting .whl files.
#
# Usage:
#   bash scripts/fetch-wheels.sh [--version VERSION]
#
# Options:
#   --version VERSION   clang-format version to fetch (default: 22.1.1)
# =============================================================================

set -euo pipefail

CF_VERSION="22.1.1"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) CF_VERSION="$2"; shift 2 ;;
        -h|--help) grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'; exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_DIR="${SUBMODULE_ROOT}/python-packages"

# Find Python
PYTHON=""
for candidate in python3 python python3.14 python3.13 python3.12 python3.11; do
    command -v "${candidate}" &>/dev/null && { PYTHON="${candidate}"; break; }
done
[[ -z "${PYTHON}" ]] && { echo "ERROR: Python 3 not found." >&2; exit 1; }

echo "=================================================================="
echo "  fetch-wheels.sh  [MAINTAINER TOOL]"
echo "  clang-format version : ${CF_VERSION}"
echo "  Output directory     : ${PKG_DIR}"
echo "=================================================================="
echo ""

mkdir -p "${PKG_DIR}"

# Download Windows x64
echo "  Downloading Windows x64..."
"${PYTHON}" -m pip download "clang-format==${CF_VERSION}" \
    --only-binary=:all: \
    --platform win_amd64 \
    --python-version 3 \
    --abi none \
    --no-deps \
    -d "${PKG_DIR}"

# Download Linux x64 (manylinux covers RHEL 8 / glibc 2.17+)
echo "  Downloading Linux x64 (manylinux)..."
"${PYTHON}" -m pip download "clang-format==${CF_VERSION}" \
    --only-binary=:all: \
    --platform manylinux_2_27_x86_64 \
    --python-version 3 \
    --abi none \
    --no-deps \
    -d "${PKG_DIR}"

# Download pip wheel (for bootstrapping venv on machines with outdated pip)
echo "  Downloading pip..."
"${PYTHON}" -m pip download pip \
    --only-binary=:all: \
    --no-deps \
    -d "${PKG_DIR}"

echo ""
echo "  Downloaded:"
ls -lh "${PKG_DIR}"/*.whl 2>/dev/null | awk '{print "    " $5 "  " $9}'
echo ""
echo "  Commit these files:"
echo "    git add python-packages/"
echo "    git commit -m \"vendor: clang-format ${CF_VERSION} wheels\""