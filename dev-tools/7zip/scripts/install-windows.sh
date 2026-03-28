#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/7zip/scripts/install-windows.sh
#
# Installs 7-Zip 26.00 on Windows (Git Bash / MINGW64).
#
# Admin mode : runs the silent .exe installer → C:\Program Files\7-Zip\7z.exe
# User mode  : extracts 7za.exe from extra package → %LOCALAPPDATA%\...\7za.exe
#
# USAGE:
#   bash scripts/install-windows.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/7zip"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"

INSTALLER="${VENDOR_DIR}/7z2600-x64.exe"
EXTRA_ARCHIVE="${VENDOR_DIR}/7z2600-extra.7z"

# ===========================================================================
# Admin install — silent .exe installer
# ===========================================================================
if [[ "${MODE}" == "admin" ]]; then
  if [[ -n "${PREFIX_OVERRIDE}" ]]; then
    INSTALL_DIR="$(cygpath -w "${PREFIX_OVERRIDE}")"
  else
    INSTALL_DIR='C:\Program Files\7-Zip'
  fi

  echo "[7zip] Admin install via silent .exe installer"
  echo "[7zip] Destination : ${INSTALL_DIR}"
  echo ""

  if [[ ! -f "${INSTALLER}" ]]; then
    echo "ERROR: Installer not found: ${INSTALLER}" >&2
    exit 1
  fi

  WIN_INSTALLER="$(cygpath -w "${INSTALLER}")"

  echo "[7zip] Running installer (requires elevation)..."
  # /S = silent, /D= sets install directory (must be last, no quotes)
  powershell.exe -NoProfile -NonInteractive -Command \
    "Start-Process -FilePath '${WIN_INSTALLER}' -ArgumentList '/S' -Verb RunAs -Wait"

  INSTALLED_BIN="/c/Program Files/7-Zip/7z.exe"
  if [[ ! -f "${INSTALLED_BIN}" ]]; then
    echo "ERROR: Installation may have failed — 7z.exe not found at expected location." >&2
    exit 1
  fi

  echo "[7zip] Installed : ${INSTALLED_BIN}"
  VER="$("${INSTALLED_BIN}" --version 2>&1 | head -1)"
  echo "[7zip] Verified  : ${VER}"
  echo ""
  echo "[7zip] NOTE: C:\\Program Files\\7-Zip is added to PATH by the installer."
  echo "       Open a new terminal for PATH to take effect."

# ===========================================================================
# User install — portable 7za.exe from extra package
# ===========================================================================
else
  if [[ -n "${PREFIX_OVERRIDE}" ]]; then
    INSTALL_DIR="${PREFIX_OVERRIDE}"
  else
    INSTALL_DIR="${LOCALAPPDATA}/airgap-cpp-devkit/7zip"
  fi

  echo "[7zip] User install — portable 7za.exe (no admin required)"
  echo "[7zip] Destination : ${INSTALL_DIR}"
  echo ""

  if [[ ! -f "${EXTRA_ARCHIVE}" ]]; then
    echo "ERROR: Extra archive not found: ${EXTRA_ARCHIVE}" >&2
    exit 1
  fi

  mkdir -p "${INSTALL_DIR}"

  # We need 7z to extract 7z2600-extra.7z — bootstrap from the installer or
  # use PowerShell Expand-Archive if available. Since the .7z format isn't
  # natively supported by PowerShell, we use the installer's bundled 7z if
  # it's already installed, otherwise fall back to a temp extraction.
  SEVEN_Z=""
  if command -v 7z &>/dev/null; then
    SEVEN_Z="7z"
  elif [[ -f "/c/Program Files/7-Zip/7z.exe" ]]; then
    SEVEN_Z="/c/Program Files/7-Zip/7z.exe"
  else
    echo "ERROR: 7z is not available. For the first-time user install, run the" >&2
    echo "       admin install first to get 7z.exe, then re-run user install." >&2
    echo "       Alternatively, manually extract x64/7za.exe from 7z2600-extra.7z" >&2
    echo "       and place it in: ${INSTALL_DIR}" >&2
    exit 1
  fi

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "${TMPDIR}"' EXIT

  echo "[7zip] Extracting x64/7za.exe from extra package..."
  "${SEVEN_Z}" e "${EXTRA_ARCHIVE}" "x64/7za.exe" -o"${TMPDIR}" -y > /dev/null

  if [[ ! -f "${TMPDIR}/7za.exe" ]]; then
    echo "ERROR: 7za.exe not found after extraction." >&2
    exit 1
  fi

  cp "${TMPDIR}/7za.exe" "${INSTALL_DIR}/7za.exe"
  echo "[7zip] Installed : ${INSTALL_DIR}/7za.exe"

  VER="$("${INSTALL_DIR}/7za.exe" 2>&1 | head -1 || true)"
  echo "[7zip] Verified  : ${VER}"
  echo ""
  echo "[7zip] NOTE: Add to PATH in your shell profile (~/.bashrc or ~/.bash_profile):"
  echo "         export PATH=\"${INSTALL_DIR}:\${PATH}\""
  echo "       Or via PowerShell (user PATH, no admin):"
  WIN_DIR="$(cygpath -w "${INSTALL_DIR}")"
  echo "         [Environment]::SetEnvironmentVariable('Path', \$env:Path + ';${WIN_DIR}', 'User')"
fi