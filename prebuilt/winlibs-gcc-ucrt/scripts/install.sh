#!/usr/bin/env bash
# Author: Nima Shafie
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
#   7z (7-Zip) — searched on PATH and in known install locations automatically.
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
# Locate 7z — PATH first, then known fallback locations
# ---------------------------------------------------------------------------
_7Z=""
_7Z_CANDIDATES=(
    "$(command -v 7z 2>/dev/null || true)"
    "/c/Program Files/7-Zip/7z.exe"
    "/c/Program Files (x86)/7-Zip/7z.exe"
    "/c/Users/${USERNAME:-${USER:-}}/AppData/Local/SourceTree/app-3.4.26/tools/7z.exe"
    "/c/Users/${USERNAME:-${USER:-}}/AppData/Local/SourceTree/app-3.4.21/tools/7z.exe"
)

for _candidate in "${_7Z_CANDIDATES[@]}"; do
    [[ -n "${_candidate}" && -x "${_candidate}" ]] && { _7Z="${_candidate}"; break; }
done

if [[ -z "${_7Z}" ]]; then
    # Last resort: search AppData for any SourceTree-bundled 7z.exe
    _found="$(find "/c/Users/${USERNAME:-${USER:-}}/AppData/Local/SourceTree" \
        -name "7z.exe" 2>/dev/null | sort -V | tail -1 || true)"
    [[ -n "${_found}" && -x "${_found}" ]] && _7Z="${_found}"
fi

if [[ -z "${_7Z}" ]]; then
    echo "[ERROR] 7z not found. Please install 7-Zip:" >&2
    echo "        https://7-zip.org/" >&2
    echo "        Or add 7z to this devkit (task: add 7z to prebuilt-binaries)." >&2
    exit 1
fi

echo "[INFO]  Using 7z: ${_7Z}"

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

"${_7Z}" x "${ARCHIVE}" -o"${STAGING}" -y > /dev/null

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