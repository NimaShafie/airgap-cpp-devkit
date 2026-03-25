#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/verify.sh
#
# Offline SHA256 verification of split parts (from prebuilt-binaries
# submodule) or the reassembled .7z (from vendor/).
#
# USAGE:
#   bash scripts/verify.sh [x86_64|i686]     # default: x86_64
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${MODULE_ROOT}/../.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
VENDOR_DIR="${MODULE_ROOT}/vendor"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/winlibs-gcc-ucrt"

ARCH="${1:-x86_64}"
if [[ "${ARCH}" != "x86_64" && "${ARCH}" != "i686" ]]; then
  echo "[ERROR] Unknown architecture '${ARCH}'. Use 'x86_64' or 'i686'." >&2
  exit 1
fi

get_assembled_filename() {
  grep -A 2 "\"${ARCH}\"" "${MANIFEST}" \
    | grep '"filename"' | grep -v 'part-' | head -1 \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/'
}

get_reassembled_hash() {
  grep -A 5 '"sha256_reassembled"' "${MANIFEST}" \
    | grep '"value"' | head -1 \
    | sed 's/.*"value": *"\([^"]*\)".*/\1/'
}

get_part_filenames() {
  grep '"filename".*part-' "${MANIFEST}" \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/'
}

get_part_hash() {
  local part_filename="$1"
  grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
    | grep '"sha256"' \
    | sed 's/.*"sha256": *"\([^"]*\)".*/\1/'
}

ASSEMBLED_FILENAME=$(get_assembled_filename)
ASSEMBLED_PATH="${VENDOR_DIR}/${ASSEMBLED_FILENAME}"
EXPECTED_ASSEMBLED_SHA256=$(get_reassembled_hash)

echo "============================================================"
echo " WinLibs GCC UCRT -- Offline Verify"
echo " Arch : ${ARCH}"
echo "============================================================"
echo ""

# If assembled .7z exists in vendor/, verify that
if [[ -f "${ASSEMBLED_PATH}" ]]; then
  echo "[MODE] Reassembled archive found -- verifying .zip..."
  ACTUAL=$(sha256sum "${ASSEMBLED_PATH}" | awk '{print $1}')
  echo "  Expected: ${EXPECTED_ASSEMBLED_SHA256}"
  echo "  Actual  : ${ACTUAL}"
  if [[ "${ACTUAL}" == "${EXPECTED_ASSEMBLED_SHA256}" ]]; then
    echo "[PASS] Archive integrity confirmed."
    exit 0
  else
    echo "[FAIL] Hash mismatch." >&2
    exit 1
  fi
fi

# Otherwise verify parts from prebuilt-binaries submodule
echo "[MODE] Verifying split parts from prebuilt-binaries submodule..."
echo "       Parts dir: ${PREBUILT_DIR}/"
echo ""

if [[ ! -d "${PREBUILT_DIR}" ]] || [[ -z "$(ls -A "${PREBUILT_DIR}" 2>/dev/null)" ]]; then
  echo "[ERROR] prebuilt-binaries submodule not initialized." >&2
  echo "        Run: bash scripts/setup-prebuilt-submodule.sh" >&2
  exit 1
fi

ALL_OK=true
FOUND=0

while IFS= read -r part_filename; do
  part_path="${PREBUILT_DIR}/${part_filename}"
  expected_hash=$(get_part_hash "${part_filename}")

  if [[ ! -f "${part_path}" ]]; then
    echo "  [FAIL] Missing: ${part_filename}" >&2
    ALL_OK=false
    continue
  fi

  actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')
  FOUND=$((FOUND + 1))

  if [[ "${actual_hash}" == "${expected_hash}" ]]; then
    echo "  [PASS] ${part_filename}"
  else
    echo "  [FAIL] ${part_filename}" >&2
    echo "         Expected : ${expected_hash}" >&2
    echo "         Actual   : ${actual_hash}" >&2
    ALL_OK=false
  fi
done < <(get_part_filenames)

echo ""
if [[ "${FOUND}" -eq 0 ]]; then
  echo "[ERROR] No parts found in ${PREBUILT_DIR}/." >&2
  exit 1
fi
if [[ "${ALL_OK}" == "true" ]]; then
  echo "[PASS] All ${FOUND} parts verified."
  echo " Next: bash scripts/reassemble.sh ${ARCH}"
else
  echo "[FAIL] One or more parts failed verification." >&2
  exit 1
fi
