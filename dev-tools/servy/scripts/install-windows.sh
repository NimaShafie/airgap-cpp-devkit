#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/servy/scripts/install-windows.sh
#
# Reassembles, extracts, and installs Servy 7.3 on Windows (Git Bash/MINGW64).
#
# Admin mode : C:\Program Files\servy\
# User mode  : %LOCALAPPDATA%\airgap-cpp-devkit\servy\
#
# USAGE:
#   bash scripts/install-windows.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/servy"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"

PART_AA="${VENDOR_DIR}/servy-7.3-x64-portable.7z.part-aa"
PART_AB="${VENDOR_DIR}/servy-7.3-x64-portable.7z.part-ab"

# Determine install destination
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_DIR="/c/Program Files/servy"
else
  INSTALL_DIR="${LOCALAPPDATA}/airgap-cpp-devkit/servy"
fi

echo "[servy] Install mode : ${MODE}"
echo "[servy] Install dir  : ${INSTALL_DIR}"
echo ""

mkdir -p "${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Find 7z/7za/7zz for extraction
# ---------------------------------------------------------------------------
SEVEN_Z=""
for candidate in \
  "/c/Program Files/7-Zip/7z.exe" \
  "${LOCALAPPDATA}/airgap-cpp-devkit/7zip/7za.exe" \
  "7z" "7za"; do
  if command -v "${candidate}" &>/dev/null 2>&1 || [[ -f "${candidate}" ]]; then
    SEVEN_Z="${candidate}"
    break
  fi
done

if [[ -z "${SEVEN_Z}" ]]; then
  echo "ERROR: No 7z/7za executable found." >&2
  echo "       Install 7-Zip first: bash dev-tools/7zip/setup.sh" >&2
  exit 1
fi

echo "[servy] Using archiver: ${SEVEN_Z}"
echo ""

# ---------------------------------------------------------------------------
# Reassemble parts into a temp .7z
# ---------------------------------------------------------------------------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

REASSEMBLED="${TMPDIR}/servy-7.3-x64-portable.7z"

echo "[servy] Reassembling parts..."
cat "${PART_AA}" "${PART_AB}" > "${REASSEMBLED}"

# Verify reassembled hash
EXPECTED_SHA="e7767b2903affc189cbf0308f4df57b87f7f73b798155d5e2574732cd7e657d6"
ACTUAL_SHA="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]]; then
  echo "ERROR: Reassembled archive SHA256 mismatch." >&2
  echo "       Expected : ${EXPECTED_SHA}" >&2
  echo "       Got      : ${ACTUAL_SHA}" >&2
  exit 1
fi
echo "[servy] Reassembled archive verified OK"
echo ""

# ---------------------------------------------------------------------------
# Extract to install dir
# ---------------------------------------------------------------------------
echo "[servy] Extracting to ${INSTALL_DIR}..."
EXTRACT_TMP="${TMPDIR}/extract"
mkdir -p "${EXTRACT_TMP}"

"${SEVEN_Z}" x "${REASSEMBLED}" -o"${EXTRACT_TMP}" -y > /dev/null

# The archive extracts to servy-7.3-x64-portable/ subdirectory — flatten one level
EXTRACTED_ROOT="${EXTRACT_TMP}/servy-7.3-x64-portable"
if [[ ! -d "${EXTRACTED_ROOT}" ]]; then
  echo "ERROR: Expected extracted folder 'servy-7.3-x64-portable' not found." >&2
  exit 1
fi

# Copy contents into install dir
cp -r "${EXTRACTED_ROOT}/." "${INSTALL_DIR}/"
echo "[servy] Installed to: ${INSTALL_DIR}"
echo ""

# ---------------------------------------------------------------------------
# Verify key binaries
# ---------------------------------------------------------------------------
for bin in servy-cli.exe Servy.exe Servy.Manager.exe Servy.psm1; do
  if [[ -f "${INSTALL_DIR}/${bin}" ]]; then
    echo "[servy] Found: ${bin}"
  else
    echo "WARNING: Expected file not found after install: ${bin}" >&2
  fi
done
echo ""

# ---------------------------------------------------------------------------
# Register PATH (user PATH — no admin required for this step)
# ---------------------------------------------------------------------------
WIN_INSTALL_DIR="$(cygpath -w "${INSTALL_DIR}")"

echo "[servy] Registering PATH entry..."
powershell.exe -NoProfile -NonInteractive -Command "
  \$scope = if ('${MODE}' -eq 'admin') { 'Machine' } else { 'User' }
  \$current = [Environment]::GetEnvironmentVariable('Path', \$scope)
  if (\$current -notlike '*${WIN_INSTALL_DIR}*') {
    [Environment]::SetEnvironmentVariable('Path', \$current + ';${WIN_INSTALL_DIR}', \$scope)
    Write-Host '[servy] PATH updated (' + \$scope + ')'
  } else {
    Write-Host '[servy] PATH already contains install dir'
  }
" 2>/dev/null || true

echo ""
echo "[servy] NOTE: Open a new terminal for PATH to take effect."
echo "       Then verify with: servy-cli.exe --version --quiet"