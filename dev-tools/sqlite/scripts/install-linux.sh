#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/sqlite/scripts/install-linux.sh
#
# Installs the SQLite CLI on Linux.
#
# Strategy:
#   - RHEL/Rocky/CentOS 8 (GLIBC < 2.29): use vendored RPM (sqlite 3.26.0)
#     because the sqlite.org prebuilt binary requires GLIBC >= 2.29.
#   - All other Linux: extract sqlite3 from the sqlite.org CLI zip (3.53.0).
#
# USAGE:
#   bash scripts/install-linux.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/sqlite"

# ---------------------------------------------------------------------------
# Detect RHEL 8 / Rocky 8 / CentOS 8 (GLIBC < 2.29)
# ---------------------------------------------------------------------------
_is_rhel8() {
  if [[ -f /etc/os-release ]]; then
    local id ver
    id="$(. /etc/os-release && echo "${ID:-}")"
    ver="$(. /etc/os-release && echo "${VERSION_ID:-}" | cut -d. -f1)"
    if [[ "${id}" =~ ^(rhel|rocky|centos|almalinux)$ && "${ver}" == "8" ]]; then
      return 0
    fi
  fi
  return 1
}

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

mkdir -p "${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
if _is_rhel8; then
  # RHEL 8 path: install via RPM (sqlite 3.26.0, GLIBC 2.17 compatible)
  RPM="${VENDOR_DIR}/sqlite-3.26.0-20.el8_10.x86_64.rpm"

  echo "[sqlite] Platform    : RHEL/Rocky 8 (GLIBC < 2.29 detected)"
  echo "[sqlite] Install mode: ${MODE}"
  echo "[sqlite] Source      : ${RPM}"
  echo ""

  if [[ ! -f "${RPM}" ]]; then
    echo "ERROR: RHEL 8 RPM not found: ${RPM}" >&2
    exit 1
  fi

  if [[ "${MODE}" == "admin" ]]; then
    # Install RPM system-wide -- places sqlite3 at /usr/bin/sqlite3
    rpm -i --nodeps "${RPM}" 2>/dev/null || rpm -U --nodeps "${RPM}" 2>/dev/null || true
    # Do NOT copy to /usr/local/bin -- RPM already installs to /usr/bin/sqlite3
    SQLITE_BIN="/usr/bin/sqlite3"
  else
    # Extract RPM contents and copy binary to user dir (no root needed)
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "${TMPDIR}"' EXIT
    cd "${TMPDIR}"
    rpm2cpio "${RPM}" | cpio -idm --quiet 2>/dev/null
    found_bin="$(find "${TMPDIR}" -name "sqlite3" -type f | head -1)"
    if [[ -z "${found_bin}" ]]; then
      echo "ERROR: sqlite3 not found in RPM after extraction." >&2
      exit 1
    fi
    chmod +x "${found_bin}"
    cp "${found_bin}" "${INSTALL_DIR}/sqlite3"
    SQLITE_BIN="${INSTALL_DIR}/sqlite3"
  fi

else
  # All other Linux: use sqlite.org prebuilt CLI zip (3.53.0)
  ARCHIVE="${VENDOR_DIR}/sqlite-tools-linux-x64-3530000.zip"

  echo "[sqlite] Install mode : ${MODE}"
  echo "[sqlite] Install dir  : ${INSTALL_DIR}"
  echo "[sqlite] Source       : ${ARCHIVE}"
  echo ""

  if [[ ! -f "${ARCHIVE}" ]]; then
    echo "ERROR: Archive not found: ${ARCHIVE}" >&2
    exit 1
  fi

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "${TMPDIR}"' EXIT

  if command -v unzip &>/dev/null; then
    unzip -q "${ARCHIVE}" -d "${TMPDIR}"
  else
    echo "ERROR: unzip not found. Install it with: sudo dnf install unzip" >&2
    exit 1
  fi

  found_bin="$(find "${TMPDIR}" -name "sqlite3" -type f | head -1)"
  if [[ -z "${found_bin}" ]]; then
    echo "ERROR: sqlite3 binary not found in archive after extraction." >&2
    exit 1
  fi

  chmod +x "${found_bin}"
  cp "${found_bin}" "${INSTALL_DIR}/sqlite3"
  SQLITE_BIN="${INSTALL_DIR}/sqlite3"
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
echo "[sqlite] Installed : ${SQLITE_BIN}"
VER="$("${SQLITE_BIN}" --version 2>/dev/null | awk '{print $1}' || echo "unknown")"
echo "[sqlite] Verified  : ${VER}"

if [[ "${MODE}" == "user" ]]; then
  echo ""
  echo "[sqlite] NOTE: Ensure ${INSTALL_DIR} is in your PATH."
  echo "         Add to ~/.bashrc if needed:"
  echo "           export PATH=\"${INSTALL_DIR}:\${PATH}\""
fi