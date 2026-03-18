#!/usr/bin/env bash
# =============================================================================
# grpc-source-build/scripts/reassemble.sh
#
# PURPOSE: Verify each split part, reassemble into the original .tar.gz,
#          then verify the reassembled tarball against the manifest SHA256.
#
#          For single-part archives (current gRPC 1.76.0), this is effectively
#          a verified copy. The pattern is kept consistent with other modules
#          so it works correctly if parts are ever added in future versions.
#
# USAGE:
#   bash scripts/reassemble.sh
#
# EXIT CODES:
#   0 - success
#   1 - failure
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
VENDOR_DIR="${MODULE_ROOT}/vendor"

get_tarball_filename() {
  grep '"tarball_filename"' "${MANIFEST}" | head -1 \
    | sed 's/.*"tarball_filename": *"\([^"]*\)".*/\1/' || true
}

get_reassembled_hash() {
  grep -A 3 '"sha256_reassembled"' "${MANIFEST}" \
    | grep '"value"' | head -1 \
    | sed 's/.*"value": *"\([^"]*\)".*/\1/' || true
}

get_part_filenames() {
  grep '"filename".*part-' "${MANIFEST}" \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/' || true
}

get_part_hash() {
  local part_filename="$1"
  grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
    | grep '"sha256"' \
    | sed 's/.*"sha256": *"\([^"]*\)".*/\1/' || true
}

TARBALL=$(get_tarball_filename)
EXPECTED_HASH=$(get_reassembled_hash)
OUTPUT="${VENDOR_DIR}/${TARBALL}"

echo "============================================================"
echo " grpc-source-build -- Reassemble"
echo " Output: ${OUTPUT}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify parts
# ---------------------------------------------------------------------------
echo "[STEP 1/3] Verifying split parts..."

PARTS=()
ALL_OK=true

while IFS= read -r part_filename; do
  [[ -z "${part_filename}" ]] && continue
  part_path="${VENDOR_DIR}/${part_filename}"
  expected_hash=$(get_part_hash "${part_filename}")

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
done < <(get_part_filenames)

if [[ "${ALL_OK}" == "false" ]]; then
  echo "" >&2
  echo "[ABORT] Part verification failed." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Reassemble
# ---------------------------------------------------------------------------
echo "[STEP 2/3] Reassembling ${#PARTS[@]} part(s) into ${TARBALL}..."

rm -f "${OUTPUT}"
cat "${PARTS[@]}" > "${OUTPUT}"

echo "[INFO] Done. Size: $(du -h "${OUTPUT}" | awk '{print $1}')"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Verify reassembled tarball
# ---------------------------------------------------------------------------
echo "[STEP 3/3] Verifying reassembled tarball SHA256..."
ACTUAL=$(sha256sum "${OUTPUT}" | awk '{print $1}')

echo "  Expected (manifest): ${EXPECTED_HASH}"
echo "  Actual             : ${ACTUAL}"
echo ""

if [[ "${ACTUAL}" == "${EXPECTED_HASH}" ]]; then
  echo "[PASS] Tarball integrity confirmed."
  echo ""
  echo "============================================================"
  echo " [SUCCESS] Ready to extract."
  echo " Run: bash setup.sh"
  echo "============================================================"
else
  echo "[FAIL] Tarball hash mismatch." >&2
  rm -f "${OUTPUT}"
  exit 1
fi
