#!/usr/bin/env bash
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/install.sh
#
# PURPOSE: Extract the reassembled .7z to the toolchain directory and smoke
#          test the result. Called by setup.sh — not intended to be run
#          directly by end users.
#
# USAGE (direct):
#   bash scripts/install.sh [x86_64|i686] [install_dir]
#
#   install_dir defaults to: <module_root>/toolchain/<arch>
#
# REQUIREMENTS:
#   7z (7-Zip) must be on PATH. On Windows Git Bash, install 7-Zip and add
#   "C:/Program Files/7-Zip" to PATH, or place 7z.exe in a PATH directory.
#
#   The reassembled .7z must already exist in vendor/ — run setup.sh or
#   reassemble.sh first.
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
# Check for 7z
# ---------------------------------------------------------------------------
if ! command -v 7z &>/dev/null; then
  echo "[ERROR] 7z not found on PATH." >&2
  echo "        Install 7-Zip (https://7-zip.org/) and add it to PATH." >&2
  echo "        On MINGW64: add 'C:/Program Files/7-Zip' to your PATH." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
echo "[extract] Extracting archive..."
mkdir -p "${INSTALL_DIR}"

STAGING="${INSTALL_DIR}/.winlibs-staging-$$"
mkdir -p "${STAGING}"

cleanup_staging() {
  rm -rf "${STAGING}"
}
trap cleanup_staging EXIT

7z x "${ARCHIVE}" -o"${STAGING}" -y > /dev/null

EXTRACTED="${STAGING}/${EXTRACT_ROOT}"
if [[ ! -d "${EXTRACTED}" ]]; then
  echo "[ERROR] Expected extraction root '${EXTRACT_ROOT}' not found in archive." >&2
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