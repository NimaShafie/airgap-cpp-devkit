#!/usr/bin/env bash
# =============================================================================
# clang-llvm-source-build/scripts/reassemble-llvm.sh
#
# PURPOSE: Verify each LLVM split part, reassemble them into the source
#          tarball, then verify the reassembled file against the official
#          upstream SHA256 pinned in manifest.json.
#
#          Run this once after cloning, before running extract-llvm-source.sh
#          or bootstrap.sh.
#
# USAGE:
#   bash scripts/reassemble-llvm.sh
#
# EXIT CODES:
#   0 — reassembly succeeded, all hashes match
#   1 — any hash mismatch or missing part
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
LLVM_SRC="${MODULE_ROOT}/llvm-src"

# ---------------------------------------------------------------------------
# Manifest parsing helpers
# ---------------------------------------------------------------------------
get_llvm_tarball() {
  grep '"tarball_filename"' "${MANIFEST}" | head -1 \
    | sed 's/.*"tarball_filename": *"\([^"]*\)".*/\1/'
}

get_llvm_reassembled_hash() {
  grep -A 3 '"sha256_reassembled"' "${MANIFEST}" \
    | grep '"value"' | head -1 \
    | sed 's/.*"value": *"\([^"]*\)".*/\1/'
}

get_llvm_part_filenames() {
  grep '"filename".*part-' "${MANIFEST}" \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/'
}

get_llvm_part_hash() {
  local part_filename="$1"
  grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
    | grep '"sha256"' \
    | sed 's/.*"sha256": *"\([^"]*\)".*/\1/'
}

TARBALL=$(get_llvm_tarball)
EXPECTED_HASH=$(get_llvm_reassembled_hash)
OUTPUT="${LLVM_SRC}/${TARBALL}"

echo "============================================================"
echo " clang-llvm-source-build — Reassemble LLVM Source"
echo " Output: ${OUTPUT}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify each part
# ---------------------------------------------------------------------------
echo "[STEP 1/3] Verifying split parts..."

PARTS=()
ALL_OK=true

while IFS= read -r part_filename; do
  part_path="${LLVM_SRC}/${part_filename}"
  expected_hash=$(get_llvm_part_hash "${part_filename}")

  if [[ ! -f "${part_path}" ]]; then
    echo "  [FAIL] Missing: ${part_filename}" >&2
    ALL_OK=false
    continue
  fi

  actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')

  if [[ "${actual_hash}" == "${expected_hash}" ]]; then
    echo "  [PASS] ${part_filename}"
    PARTS+=("${part_path}")
  else
    echo "  [FAIL] ${part_filename}" >&2
    echo "         Expected : ${expected_hash}" >&2
    echo "         Actual   : ${actual_hash}" >&2
    ALL_OK=false
  fi
done < <(get_llvm_part_filenames)

if [[ "${ALL_OK}" == "false" ]]; then
  echo "" >&2
  echo "[ABORT] Part verification failed. Cannot reassemble." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Reassemble
# ---------------------------------------------------------------------------
echo "[STEP 2/3] Reassembling ${#PARTS[@]} parts into ${TARBALL}..."

rm -f "${OUTPUT}"
cat "${PARTS[@]}" > "${OUTPUT}"

echo "[INFO] Done. Size: $(du -h "${OUTPUT}" | awk '{print $1}')"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Verify reassembled tarball
# ---------------------------------------------------------------------------
echo "[STEP 3/3] Verifying reassembled tarball SHA256..."
ACTUAL=$(sha256sum "${OUTPUT}" | awk '{print $1}')

echo "  Expected (official upstream): ${EXPECTED_HASH}"
echo "  Actual                      : ${ACTUAL}"
echo ""

if [[ "${ACTUAL}" == "${EXPECTED_HASH}" ]]; then
  echo "[PASS] Reassembled tarball integrity confirmed."
  echo ""
  echo "============================================================"
  echo " [SUCCESS] Ready to extract."
  echo " Run: bash scripts/extract-llvm-source.sh"
  echo "============================================================"
else
  echo "[FAIL] Reassembled tarball hash mismatch." >&2
  echo "       Parts passed individually but joined file is wrong." >&2
  rm -f "${OUTPUT}"
  exit 1
fi