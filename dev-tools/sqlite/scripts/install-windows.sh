#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/sqlite/scripts/install-windows.sh
#
# Extracts sqlite3.exe from the SQLite tools zip and installs it.
# Called by setup.sh after verification.
#
# USAGE:
#   bash scripts/install-windows.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"
VERSION="3.53.0"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/sqlite"
ARCHIVE="${VENDOR_DIR}/sqlite-tools-win-x64-3530000.zip"

# ---------------------------------------------------------------------------
# Determine install directory
# ---------------------------------------------------------------------------
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}/bin"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_DIR="/c/Program Files/airgap-cpp-devkit/sqlite/bin"
else
  LOCALAPPDATA_UNIX="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null || echo "${HOME}/AppData/Local")"
  INSTALL_DIR="${LOCALAPPDATA_UNIX}/airgap-cpp-devkit/sqlite/bin"
fi

echo "[sqlite] Install mode : ${MODE}"
echo "[sqlite] Install dir  : ${INSTALL_DIR}"
echo "[sqlite] Source       : ${ARCHIVE}"
echo ""

if [[ ! -f "${ARCHIVE}" ]]; then
  echo "ERROR: Archive not found: ${ARCHIVE}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Extract sqlite3.exe from zip
# ---------------------------------------------------------------------------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

if command -v unzip &>/dev/null; then
  unzip -q -o "${ARCHIVE}" -d "${TMPDIR}"
elif command -v 7z &>/dev/null; then
  7z x "${ARCHIVE}" -o"${TMPDIR}" -y > /dev/null
else
  echo "ERROR: Need unzip or 7z to extract. Install dev-tools/7zip first." >&2
  exit 1
fi

found_exe="$(find "${TMPDIR}" -name "sqlite3.exe" | head -1)"
if [[ -z "${found_exe}" ]]; then
  echo "ERROR: sqlite3.exe not found in archive after extraction." >&2
  exit 1
fi

cp "${found_exe}" "${INSTALL_DIR}/sqlite3.exe"
echo "[sqlite] Installed : ${INSTALL_DIR}/sqlite3.exe"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
VER="$("${INSTALL_DIR}/sqlite3.exe" --version 2>/dev/null | awk '{print $1}' || echo "unknown")"
echo "[sqlite] Verified  : ${VER}"

# ---------------------------------------------------------------------------
# Register PATH
# ---------------------------------------------------------------------------
INSTALL_DIR_WIN="$(cygpath -w "${INSTALL_DIR}" 2>/dev/null || echo "${INSTALL_DIR}")"

if [[ "${MODE}" == "admin" ]]; then
  powershell.exe -NoProfile -Command "
    \$path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (\$path -notlike '*${INSTALL_DIR_WIN}*') {
      [System.Environment]::SetEnvironmentVariable('Path', \$path + ';${INSTALL_DIR_WIN}', 'Machine')
      Write-Host '[sqlite] PATH registered (Machine scope)'
    } else {
      Write-Host '[sqlite] PATH already registered (Machine scope)'
    }
  " 2>/dev/null || echo "[sqlite] Could not register PATH -- add manually: ${INSTALL_DIR_WIN}"
else
  powershell.exe -NoProfile -Command "
    \$path = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if (\$path -notlike '*${INSTALL_DIR_WIN}*') {
      [System.Environment]::SetEnvironmentVariable('Path', \$path + ';${INSTALL_DIR_WIN}', 'User')
      Write-Host '[sqlite] PATH registered (User scope)'
    } else {
      Write-Host '[sqlite] PATH already registered (User scope)'
    }
  " 2>/dev/null || echo "[sqlite] Could not register PATH -- add manually: ${INSTALL_DIR_WIN}"
fi