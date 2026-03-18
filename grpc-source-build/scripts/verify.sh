#!/usr/bin/env bash
# =============================================================================
# grpc-source-build/scripts/verify.sh
#
# PURPOSE: Offline SHA256 verification of vendored gRPC source archive.
#
# USAGE:
#   bash scripts/verify.sh [1.76.0|1.78.1]     # default: 1.76.0
#
# EXIT CODES:
#   0 - all checks passed
#   1 - any mismatch or missing file
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
VENDOR_DIR="${MODULE_ROOT}/vendor"

VERSION="${1:-1.76.0}"

# ---------------------------------------------------------------------------
# Parse manifest for the requested version
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
TARBALL_PATH="${VENDOR_DIR}/${TARBALL}"

echo "============================================================"
echo " grpc-source-build -- Offline Verify"
echo " Version: ${VERSION}"
echo "============================================================"
echo ""

if [[ -z "${TARBALL}" || -z "${EXPECTED_HASH}" ]]; then
  echo "[ERROR] Could not parse manifest.json for version ${VERSION}" >&2
  echo "        Available versions: 1.76.0, 1.78.1" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# If reassembled tarball present — verify it directly
# ---------------------------------------------------------------------------
if [[ -f "${TARBALL_PATH}" ]]; then
  echo "[MODE] Tarball found -- verifying directly."
  echo "       File: ${TARBALL_PATH}"
  ACTUAL=$(sha256sum "${TARBALL_PATH}" | awk '{print $1}')
  echo "  Expected (manifest): ${EXPECTED_HASH}"
  echo "  Actual             : ${ACTUAL}"
  echo ""
  if [[ "${ACTUAL}" == "${EXPECTED_HASH}" ]]; then
    echo "[PASS] Tarball integrity confirmed."
    exit 0
  else
    echo "[FAIL] Hash mismatch." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Verify parts
# ---------------------------------------------------------------------------
echo "[MODE] No tarball found -- verifying split parts."
echo ""

ALL_OK=true
FOUND=0

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
  FOUND=$((FOUND + 1))

  if [[ "${actual_hash}" == "${expected_hash}" ]]; then
    echo "  [PASS] ${part_filename}"
  else
    echo "  [FAIL] ${part_filename}" >&2
    echo "         Expected : ${expected_hash}" >&2
    echo "         Actual   : ${actual_hash}" >&2
    ALL_OK=false
  fi
done < <(get_part_filenames_for_version)

echo ""

if [[ "${FOUND}" -eq 0 ]]; then
  echo "[ERROR] No parts found in vendor/ for version ${VERSION}." >&2
  exit 1
fi

if [[ "${ALL_OK}" == "true" ]]; then
  echo "[PASS] All ${FOUND} part(s) verified for v${VERSION}."
  exit 0
else
  echo "[FAIL] One or more parts failed verification." >&2
  exit 1
fi