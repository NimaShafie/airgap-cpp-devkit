#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# install-venv.sh — Set up a Python venv with clang-format from vendored wheels
#
# Creates a self-contained Python virtual environment inside the submodule
# and installs clang-format from the committed .whl files in python-packages/.
# No network access required. No admin rights required.
#
# Called automatically by bootstrap.sh. Can also be run directly.
#
# Usage:
#   bash scripts/install-venv.sh [--force]
#
# Options:
#   --force    Recreate the venv even if it already exists.
#
# Output:
#   Creates: .venv/ inside the submodule root
#   Binary:  .venv/Scripts/clang-format.exe  (Windows)
#            .venv/bin/clang-format           (Linux)
# =============================================================================

set -euo pipefail

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
PKG_DIR="${SUBMODULE_ROOT}/python-packages"
VENV_DIR="${SUBMODULE_ROOT}/.venv"

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)                OS="linux"   ;;
    Darwin*)               OS="macos"   ;;
    *)                     OS="unknown" ;;
esac

# ---------------------------------------------------------------------------
# Locate correct clang-format wheel for this platform
# ---------------------------------------------------------------------------
CF_WHEEL=""
case "${OS}" in
    windows)
        for f in "${PKG_DIR}"/clang_format-*-win_amd64.whl; do
            [[ -f "${f}" ]] && { CF_WHEEL="${f}"; break; }
        done
        ;;
    linux)
        # Prefer manylinux (glibc) over musl — covers RHEL 8
        for f in \
            "${PKG_DIR}"/clang_format-*-manylinux*.whl \
            "${PKG_DIR}"/clang_format-*-linux*.whl; do
            [[ -f "${f}" ]] && { CF_WHEEL="${f}"; break; }
        done
        ;;
    *)
        echo "ERROR: Unsupported platform: ${OS}" >&2
        exit 1
        ;;
esac

if [[ -z "${CF_WHEEL}" ]]; then
    echo "" >&2
    echo "ERROR: No clang-format wheel found for platform '${OS}' in:" >&2
    echo "  ${PKG_DIR}" >&2
    echo "" >&2
    echo "  Expected files:" >&2
    echo "    Windows: clang_format-*-win_amd64.whl" >&2
    echo "    Linux:   clang_format-*-manylinux*.whl" >&2
    echo "" >&2
    echo "  To download wheels on a connected machine:" >&2
    echo "    bash ${SCRIPT_DIR}/fetch-wheels.sh" >&2
    exit 1
fi

CF_VERSION="$(basename "${CF_WHEEL}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
echo "  Wheel   : $(basename "${CF_WHEEL}")"
echo "  Version : clang-format ${CF_VERSION}"

# ---------------------------------------------------------------------------
# Locate pip wheel (used to upgrade pip inside the venv before installing)
# ---------------------------------------------------------------------------
PIP_WHEEL=""
for f in "${PKG_DIR}"/pip-*.whl; do
    [[ -f "${f}" ]] && { PIP_WHEEL="${f}"; break; }
done

# ---------------------------------------------------------------------------
# Check if venv already exists and is working
# ---------------------------------------------------------------------------
case "${OS}" in
    windows) VENV_CF="${VENV_DIR}/Scripts/clang-format.exe" ;;
    *)       VENV_CF="${VENV_DIR}/bin/clang-format" ;;
esac

if [[ -x "${VENV_CF}" && "${FORCE}" == "false" ]]; then
    EXISTING_VER="$("${VENV_CF}" --version 2>/dev/null | head -1)"
    echo "  Already installed: ${EXISTING_VER}"
    echo "  Use --force to reinstall."
    exit 0
fi

# ---------------------------------------------------------------------------
# Find Python 3
# ---------------------------------------------------------------------------
PYTHON=""
for candidate in python3 python python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8; do
    if command -v "${candidate}" &>/dev/null; then
        ver="$("${candidate}" -c 'import sys; print(sys.version_info.major)' 2>/dev/null)"
        [[ "${ver}" == "3" ]] && { PYTHON="${candidate}"; break; }
    fi
done

[[ -z "${PYTHON}" ]] && {
    echo "ERROR: Python 3 not found on PATH." >&2
    echo "  Install Python 3.8+ and ensure it is on PATH." >&2
    exit 1
}

PY_VER="$("${PYTHON}" --version 2>&1)"
echo "  Python  : ${PY_VER} ($(command -v "${PYTHON}"))"

# ---------------------------------------------------------------------------
# Create venv
# ---------------------------------------------------------------------------
if [[ -d "${VENV_DIR}" && "${FORCE}" == "true" ]]; then
    echo "  Removing existing venv..."
    rm -rf "${VENV_DIR}"
fi

if [[ ! -d "${VENV_DIR}" ]]; then
    echo "  Creating venv at ${VENV_DIR}..."
    "${PYTHON}" -m venv "${VENV_DIR}"
fi

# Activate venv Python
case "${OS}" in
    windows) VENV_PYTHON="${VENV_DIR}/Scripts/python.exe" ;;
    *)       VENV_PYTHON="${VENV_DIR}/bin/python" ;;
esac

# ---------------------------------------------------------------------------
# Upgrade pip inside venv from vendored wheel (no network)
# ---------------------------------------------------------------------------
if [[ -n "${PIP_WHEEL}" ]]; then
    echo "  Upgrading pip from vendored wheel..."
    "${VENV_PYTHON}" -m pip install --quiet --no-index "${PIP_WHEEL}"
fi

# ---------------------------------------------------------------------------
# Install clang-format from vendored wheel (no network, no index)
# ---------------------------------------------------------------------------
echo "  Installing clang-format from vendored wheel..."
"${VENV_PYTHON}" -m pip install \
    --quiet \
    --no-index \
    --no-deps \
    "${CF_WHEEL}"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
if [[ ! -x "${VENV_CF}" ]]; then
    echo "ERROR: clang-format not found at expected path after install:" >&2
    echo "  ${VENV_CF}" >&2
    exit 1
fi

INSTALLED_VER="$("${VENV_CF}" --version 2>/dev/null | head -1)"
echo "  Installed: ${INSTALLED_VER}"
echo "  Binary   : ${VENV_CF}"