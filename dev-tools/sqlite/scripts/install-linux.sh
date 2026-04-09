#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/sqlite/scripts/install-linux.sh
#
# Extracts the sqlite3 binary from the SQLite tools zip and installs it.
# Called by setup.sh after verification.
#
# USAGE:
#   bash scripts/install-linux.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"
VERSION="3.51.3"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/sqlite"
ARCHIVE="${VENDOR_DIR}/sqlite-tools-linux-x64-3530000.zip"

# ---------------------------------------------------------------------------
# Determine install directory
# ---------------------------------------------------------------------------
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}/bin"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="${HOME}/.local/bin"
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
# Extract sqlite3 binary
# ---------------------------------------------------------------------------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

if command -v unzip &>/dev/null; then
  unzip -q "${ARCHIVE}" -d "${TMPDIR}"
else
  echo "ERROR: unzip not found. Install it with: sudo dnf install unzip" >&2
  exit 1
fi

# sqlite3 binary may be in a subdirectory
found_bin="$(find "${TMPDIR}" -name "sqlite3" -type f | head -1)"
if [[ -z "${found_bin}" ]]; then
  echo "ERROR: sqlite3 binary not found in archive after extraction." >&2
  exit 1
fi

chmod +x "${found_bin}"
cp "${found_bin}" "${INSTALL_DIR}/sqlite3"
echo "[sqlite] Installed : ${INSTALL_DIR}/sqlite3"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
VER="$("${INSTALL_DIR}/sqlite3" --version 2>/dev/null | awk '{print $1}' || echo "unknown")"
echo "[sqlite] Verified  : ${VER}"

# ---------------------------------------------------------------------------
# PATH hint for user installs
# ---------------------------------------------------------------------------
if [[ "${MODE}" == "user" ]]; then
  echo ""
  echo "[sqlite] NOTE: Ensure ${INSTALL_DIR} is in your PATH."
  echo "       Add to ~/.bashrc if needed:"
  echo "         export PATH=\"${INSTALL_DIR}:\${PATH}\""
fi