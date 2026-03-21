#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/reassemble.sh
#
# Verifies split parts from prebuilt-binaries submodule, reassembles them
# into the .7z, and verifies the assembled archive SHA256.
#
# USAGE:
#   bash scripts/reassemble.sh [x86_64|i686]     # default: x86_64
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

get_assembled_filename() {
  grep -A 2 "\"${ARCH}\"" "${MANIFEST}" \
    | grep '"filename"' | grep -v 'part-' | head -1 \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/'
}

ASSEMBLED_FILENAME=$(get_assembled_filename)
ASSEMBLED_PATH="${VENDOR_DIR}/${ASSEMBLED_FILENAME}"
EXPECTED_ASSEMBLED_SHA256=$(get_reassembled_hash)

mkdir -p "${VENDOR_DIR}"

echo "============================================================"
echo " WinLibs GCC UCRT — Reassemble"
echo " Arch    : ${ARCH}"
echo " Parts   : ${PREBUILT_DIR}/"
echo " Output  : ${ASSEMBLED_PATH}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify each part from prebuilt-binaries submodule
# ---------------------------------------------------------------------------
echo "[STEP 1/3] Verifying split parts..."

# Check submodule is initialized
if [[ ! -d "${PREBUILT_DIR}" ]] || [[ -z "$(ls -A "${PREBUILT_DIR}" 2>/dev/null)" ]]; then
  echo "[ERROR] prebuilt-binaries submodule not initialized." >&2
  echo "        Run: bash scripts/setup-prebuilt-submodule.sh" >&2
  exit 1
fi

PARTS=()
ALL_PARTS_OK=true

while IFS= read -r part_filename; do
  part_path="${PREBUILT_DIR}/${part_filename}"
  expected_hash=$(get_part_hash "${part_filename}")

  if [[ ! -f "${part_path}" ]]; then
    echo "  [FAIL] Missing: ${part_filename} (expected in ${PREBUILT_DIR}/)" >&2
    ALL_PARTS_OK=false
    continue
  fi

  actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')

  if [[ "${actual_hash}" == "${expected_hash}" ]]; then
    echo "  [PASS] ${part_filename}"
    PARTS+=("${part_path}")
  else
    echo "  [FAIL] Hash mismatch: ${part_filename}" >&2
    echo "         Expected : ${expected_hash}" >&2
    echo "         Actual   : ${actual_hash}" >&2
    ALL_PARTS_OK=false
  fi
done < <(get_part_filenames)

if [[ "${ALL_PARTS_OK}" == "false" ]]; then
  echo "" >&2
  echo "[ABORT] One or more parts failed verification." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Reassemble into vendor/
# ---------------------------------------------------------------------------
echo "[STEP 2/3] Reassembling ${#PARTS[@]} parts into ${ASSEMBLED_FILENAME}..."
rm -f "${ASSEMBLED_PATH}"
cat "${PARTS[@]}" > "${ASSEMBLED_PATH}"
echo "[INFO] Done. Size: $(du -h "${ASSEMBLED_PATH}" | awk '{print $1}')"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Verify assembled archive
# ---------------------------------------------------------------------------
echo "[STEP 3/3] Verifying reassembled archive SHA256..."
ACTUAL=$(sha256sum "${ASSEMBLED_PATH}" | awk '{print $1}')

echo "  Expected (manifest): ${EXPECTED_ASSEMBLED_SHA256}"
echo "  Actual             : ${ACTUAL}"
echo ""

if [[ "${ACTUAL}" == "${EXPECTED_ASSEMBLED_SHA256}" ]]; then
  echo "[PASS] Reassembled archive integrity confirmed."
  echo ""
  echo "============================================================"
  echo " [SUCCESS] Ready to install."
  echo " Run: bash scripts/install.sh ${ARCH}"
  echo "============================================================"
else
  echo "[FAIL] Reassembled archive hash mismatch." >&2
  rm -f "${ASSEMBLED_PATH}"
  exit 1
fi
