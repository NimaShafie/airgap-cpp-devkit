#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/7zip/scripts/install-linux.sh
#
# Extracts and installs the 7zz binary on Linux (RHEL 8 / Rocky Linux).
#
# USAGE:
#   bash scripts/install-linux.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/7zip"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"

TARBALL="${VENDOR_DIR}/7z2600-linux-x64.tar.xz"

# Determine install destination
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="${HOME}/.local/bin"
fi

echo "[7zip] Install mode : ${MODE}"
echo "[7zip] Install dir  : ${INSTALL_DIR}"
echo "[7zip] Source       : ${TARBALL}"
echo ""

# Create destination if needed
mkdir -p "${INSTALL_DIR}"

# Extract only the 7zz binary from the tarball
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "[7zip] Extracting 7zz from tarball..."
tar -xJf "${TARBALL}" -C "${TMPDIR}" 7zz

if [[ ! -f "${TMPDIR}/7zz" ]]; then
  echo "ERROR: 7zz binary not found in tarball after extraction." >&2
  exit 1
fi

# Install
chmod +x "${TMPDIR}/7zz"
cp "${TMPDIR}/7zz" "${INSTALL_DIR}/7zz"

echo "[7zip] Installed: ${INSTALL_DIR}/7zz"
echo ""

# Verify
INSTALLED="${INSTALL_DIR}/7zz"
VER="$("${INSTALLED}" i 2>&1 | grep -i "7-Zip" | head -1 || true)"
if [[ -n "${VER}" ]]; then
  echo "[7zip] Verified : ${VER}"
else
  echo "[7zip] Verified : $(${INSTALLED} 2>&1 | head -1 || true)"
fi

# PATH hint for user installs
if [[ "${MODE}" == "user" ]]; then
  echo ""
  echo "[7zip] NOTE: Ensure ${INSTALL_DIR} is in your PATH."
  echo "       Add to ~/.bashrc if needed:"
  echo "         export PATH=\"${INSTALL_DIR}:\${PATH}\""
  echo "       Then verify with: 7zz i"
fi