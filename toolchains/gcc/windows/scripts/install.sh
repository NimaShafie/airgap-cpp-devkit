#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/gcc/windows/scripts/install.sh
#
# PURPOSE: Extract the reassembled .zip to the toolchain directory and smoke
#          test the result. Called by setup.sh — not intended to be run
#          directly by end users.
#
# USAGE (direct):
#   bash scripts/install.sh [x86_64|i686] [install_dir]
#
#   install_dir defaults to: <module_root>/toolchain/<arch>
#
# EXTRACTION:
#   Uses PowerShell Expand-Archive (Windows native, no external tools needed).
#   Falls back to 7z if available.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
VENDOR_DIR="${MODULE_ROOT}/vendor"

ARCH="${1:-x86_64}"
if [[ "${ARCH}" != "x86_64" && "${ARCH}" != "i686" ]]; then
  echo "[ERROR] Unknown architecture '${ARCH}'. Use 'x86_64' or 'i686'." >&2
  exit 1
fi

INSTALL_DIR="${2:-${MODULE_ROOT}/toolchain/${ARCH}}"

# ---------------------------------------------------------------------------
# Parse manifest
# ---------------------------------------------------------------------------
FILENAME=$(grep -A 2 "\"${ARCH}\"" "${MANIFEST}" \
  | grep '"filename"' \
  | grep -v 'part-' \
  | head -1 \
  | sed 's/.*"filename": *"\([^"]*\)".*/\1/')

EXTRACT_ROOT=$(grep -A 40 "\"${ARCH}\"" "${MANIFEST}" \
  | grep '"extract_root"' \
  | head -1 \
  | sed 's/.*"extract_root": *"\([^"]*\)".*/\1/')

ARCHIVE="${VENDOR_DIR}/${FILENAME}"

echo " Archive     : ${ARCHIVE}"
echo " Install dir : ${INSTALL_DIR}"
echo ""

# ---------------------------------------------------------------------------
# Guard: reassembled archive must exist
# ---------------------------------------------------------------------------
if [[ ! -f "${ARCHIVE}" ]]; then
  echo "[ERROR] Reassembled archive not found: ${ARCHIVE}" >&2
  echo "        Run setup.sh to verify, reassemble, and install in one step." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract — PowerShell Expand-Archive (native, no 7z needed)
# Falls back to 7z if available on PATH
# ---------------------------------------------------------------------------
echo "[extract] Extracting archive..."
mkdir -p "${INSTALL_DIR}"

STAGING="${INSTALL_DIR}/.winlibs-staging-$$"
mkdir -p "${STAGING}"

cleanup_staging() {
  rm -rf "${STAGING}"
}
trap cleanup_staging EXIT

if command -v 7z &>/dev/null; then
    echo "[extract] Using 7z..."
    7z x "${ARCHIVE}" -o"${STAGING}" -y > /dev/null
else
    echo "[extract] Using PowerShell Expand-Archive..."
    WIN_ARCHIVE="$(cygpath -w "${ARCHIVE}")"
    WIN_STAGING="$(cygpath -w "${STAGING}")"
    powershell.exe -NoProfile -Command \
        "Expand-Archive -LiteralPath '${WIN_ARCHIVE}' -DestinationPath '${WIN_STAGING}' -Force"
fi

EXTRACTED="${STAGING}/${EXTRACT_ROOT}"
if [[ ! -d "${EXTRACTED}" ]]; then
  echo "[ERROR] Expected extraction root '${EXTRACT_ROOT}' not found in archive." >&2
  echo "        Contents of staging dir:"
  ls "${STAGING}" 2>/dev/null || true
  exit 1
fi

FINAL_PATH="${INSTALL_DIR}/${EXTRACT_ROOT}"
if [[ -d "${FINAL_PATH}" ]]; then
  echo "[extract] Removing previous install at ${FINAL_PATH}..."
  rm -rf "${FINAL_PATH}"
fi
mv "${EXTRACTED}" "${FINAL_PATH}"

echo "[extract] Done: ${FINAL_PATH}"
echo ""

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------
echo "[smoke] Testing gcc..."
GCC_BIN="${FINAL_PATH}/bin/gcc.exe"
if [[ ! -f "${GCC_BIN}" ]]; then
  echo "[WARN] gcc.exe not found at: ${GCC_BIN}" >&2
  echo "       Extraction may have produced a different layout." >&2
  exit 1
fi

GCC_VER=$("${GCC_BIN}" --version 2>&1 | head -1)
echo "[PASS] ${GCC_VER}"