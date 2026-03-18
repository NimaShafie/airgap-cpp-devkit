#!/usr/bin/env bash
# =============================================================================
# grpc-source-build/scripts/reassemble.sh
#
# PURPOSE: Verify parts and reassemble into the original .tar.gz for the
#          specified gRPC version.
#
# USAGE:
#   bash scripts/reassemble.sh [1.76.0|1.78.1]     # default: 1.76.0
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

VERSION="${1:-1.76.0}"

# ---------------------------------------------------------------------------
# Manifest parsing
# ---------------------------------------------------------------------------
get_field_for_version() {
  local field="$1"
  awk -v ver="\"${VERSION}\"" -v fld="\"${field}\"" '
    $0 ~ ver { found=1 }
    found && $0 ~ fld {
      match($0, /"'"${field}"'": *"([^"]+)"/, a)
      if (a[1] != "") { print a[1]; exit }
    }
  ' "${MANIFEST}" || true
}

get_part_filenames_for_version() {
  awk -v ver="\"${VERSION}\"" '
    $0 ~ ver { found=1 }
    found && /"filename".*part-/ {
      match($0, /"filename": *"([^"]+)"/, a)
      if (a[1] != "") print a[1]
    }
    found && /"[0-9]+\.[0-9]+\.[0-9]+"/ && $0 !~ ver { exit }
  ' "${MANIFEST}" || true
}

get_part_hash() {
  local part_filename="$1"
  grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
    | grep '"sha256"' \
    | sed 's/.*"sha256": *"\([^"]*\)".*/\1/' || true
}

TARBALL=$(get_field_for_version "tarball_filename")
EXPECTED_HASH=$(get_field_for_version "value")
OUTPUT="${VENDOR_DIR}/${TARBALL}"

echo "============================================================"
echo " grpc-source-build -- Reassemble v${VERSION}"
echo " Output: ${OUTPUT}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify parts
# ---------------------------------------------------------------------------
echo "[STEP 1/3] Verifying parts..."

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
done < <(get_part_filenames_for_version)

if [[ "${ALL_OK}" == "false" ]]; then
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
echo "[STEP 3/3] Verifying reassembled tarball..."
ACTUAL=$(sha256sum "${OUTPUT}" | awk '{print $1}')
echo "  Expected: ${EXPECTED_HASH}"
echo "  Actual  : ${ACTUAL}"
echo ""

if [[ "${ACTUAL}" == "${EXPECTED_HASH}" ]]; then
  echo "[PASS] v${VERSION} tarball integrity confirmed."
  echo ""
  echo "============================================================"
  echo " [SUCCESS] Ready. Run setup_grpc.bat to build."
  echo "============================================================"
else
  echo "[FAIL] Tarball hash mismatch." >&2
  rm -f "${OUTPUT}"
  exit 1
fi