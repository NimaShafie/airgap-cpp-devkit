#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/servy/scripts/install-windows.sh
#
# Extracts and installs the Servy 7.8 portable archive on Windows.
# Called by setup.sh after verification.
#
# USAGE:
#   bash install-windows.sh <install_mode> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

INSTALL_MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"
VERSION="7.8"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/servy"
ARCHIVE="${PREBUILT_DIR}/servy-7.8-x64-portable.7z"

# ---------------------------------------------------------------------------
# Determine install directory
# ---------------------------------------------------------------------------
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}"
elif [[ "${INSTALL_MODE}" == "admin" ]]; then
  INSTALL_DIR="/c/Program Files/servy"
else
  LOCALAPPDATA_UNIX="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null || echo "${HOME}/AppData/Local")"
  INSTALL_DIR="${LOCALAPPDATA_UNIX}/airgap-cpp-devkit/servy"
fi

echo "  Install directory: ${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Locate extractor
# ---------------------------------------------------------------------------
_find_7z() {
  if command -v 7z  &>/dev/null; then echo "7z";  return; fi
  if command -v 7za &>/dev/null; then echo "7za"; return; fi

  local devkit_7za
  devkit_7za="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null)/airgap-cpp-devkit/7zip/7za.exe"
  if [[ -f "${devkit_7za}" ]]; then echo "${devkit_7za}"; return; fi

  local sys_7z
  sys_7z="$(cygpath -u "${PROGRAMFILES:-/c/Program Files}" 2>/dev/null)/7-Zip/7z.exe"
  if [[ -f "${sys_7z}" ]]; then echo "${sys_7z}"; return; fi

  echo ""
}

EXTRACTOR="$(_find_7z)"
if [[ -z "${EXTRACTOR}" ]]; then
  echo "ERROR: No extractor found. Install dev-tools/7zip first:" >&2
  echo "       bash dev-tools/7zip/setup.sh" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract -- clean install dir first to avoid mv conflicts on rebuild
# ---------------------------------------------------------------------------
mkdir -p "${INSTALL_DIR}"

echo "  Extracting servy-7.8-x64-portable.7z..."
"${EXTRACTOR}" x "${ARCHIVE}" -o"${INSTALL_DIR}" -y > /dev/null

# Flatten if the archive extracted into a named subdirectory
for nested in "${INSTALL_DIR}/servy-7.8-x64-portable" "${INSTALL_DIR}/Servy"; do
  if [[ -d "${nested}" ]]; then
    # Use cp+rm instead of mv to handle non-empty subdirectories on rebuild
    cp -rf "${nested}/." "${INSTALL_DIR}/"
    rm -rf "${nested}"
    break
  fi
done

# ---------------------------------------------------------------------------
# Register PATH
# ---------------------------------------------------------------------------
INSTALL_DIR_WIN="$(cygpath -w "${INSTALL_DIR}" 2>/dev/null || echo "${INSTALL_DIR}")"

if [[ "${INSTALL_MODE}" == "admin" ]]; then
  powershell.exe -NoProfile -Command "
    \$path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (\$path -notlike '*${INSTALL_DIR_WIN}*') {
      [System.Environment]::SetEnvironmentVariable('Path', \$path + ';${INSTALL_DIR_WIN}', 'Machine')
      Write-Host '  [OK]  PATH registered (Machine scope)'
    } else {
      Write-Host '  [OK]  PATH already registered (Machine scope)'
    }
  " 2>/dev/null || echo "  [!!]  PATH registration requires elevation -- add manually: ${INSTALL_DIR_WIN}"
else
  powershell.exe -NoProfile -Command "
    \$path = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if (\$path -notlike '*${INSTALL_DIR_WIN}*') {
      [System.Environment]::SetEnvironmentVariable('Path', \$path + ';${INSTALL_DIR_WIN}', 'User')
      Write-Host '  [OK]  PATH registered (User scope)'
    } else {
      Write-Host '  [OK]  PATH already registered (User scope)'
    }
  " 2>/dev/null || echo "  [!!]  Could not register PATH -- add manually: ${INSTALL_DIR_WIN}"
fi

echo "  [OK]  Servy ${VERSION} installed to: ${INSTALL_DIR}"