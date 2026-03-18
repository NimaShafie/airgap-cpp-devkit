#!/usr/bin/env bash
# =============================================================================
# clang-llvm-source-build/scripts/verify-sources.sh
#
# PURPOSE: Offline SHA256 verification of all vendored source archives.
#          Checks LLVM split parts and the Ninja tarball against the hashes
#          pinned in manifest.json. No network access required.
#
#          If the reassembled LLVM tarball already exists in llvm-src/, it
#          verifies that instead of the parts.
#
# USAGE:
#   bash scripts/verify-sources.sh
#
# EXIT CODES:
#   0 - all checks passed
#   1 - any mismatch or missing file
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
LLVM_SRC="${MODULE_ROOT}/llvm-src"
NINJA_SRC="${MODULE_ROOT}/ninja-src"

echo "============================================================"
echo " clang-llvm-source-build -- Source Verification"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Manifest parsing helpers
# || true prevents set -e from killing on grep no-match
# ---------------------------------------------------------------------------

get_llvm_tarball() {
  grep '"tarball_filename"' "${MANIFEST}" | head -1 \
    | sed 's/.*"tarball_filename": *"\([^"]*\)".*/\1/' || true
}

get_llvm_reassembled_hash() {
  grep -A 3 '"sha256_reassembled"' "${MANIFEST}" \
    | grep '"value"' | head -1 \
    | sed 's/.*"value": *"\([^"]*\)".*/\1/' || true
}

get_llvm_part_filenames() {
  grep '"filename".*part-' "${MANIFEST}" \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/' || true
}

get_llvm_part_hash() {
  local part_filename="$1"
  grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
    | grep '"sha256"' \
    | sed 's/.*"sha256": *"\([^"]*\)".*/\1/' || true
}

get_ninja_tarball() {
  awk '/"ninja"/{found=1} found && /"tarball_filename"/{
    match($0, /"tarball_filename": *"([^"]+)"/, a); print a[1]; exit
  }' "${MANIFEST}" || true
}

get_ninja_hash() {
  awk '/"ninja"/{found=1} found && /"value"/{
    match($0, /"value": *"([^"]+)"/, a); print a[1]; exit
  }' "${MANIFEST}" || true
}

# ---------------------------------------------------------------------------
# Parse and validate
# ---------------------------------------------------------------------------
LLVM_TARBALL=$(get_llvm_tarball)
LLVM_REASSEMBLED_HASH=$(get_llvm_reassembled_hash)
NINJA_TARBALL=$(get_ninja_tarball)
NINJA_HASH=$(get_ninja_hash)

if [[ -z "${LLVM_TARBALL}" ]]; then
  echo "[ERROR] Could not parse LLVM tarball_filename from manifest.json" >&2; exit 1
fi
if [[ -z "${LLVM_REASSEMBLED_HASH}" ]]; then
  echo "[ERROR] Could not parse LLVM sha256_reassembled value from manifest.json" >&2; exit 1
fi
if [[ -z "${NINJA_TARBALL}" ]]; then
  echo "[ERROR] Could not parse Ninja tarball_filename from manifest.json" >&2; exit 1
fi
if [[ -z "${NINJA_HASH}" ]]; then
  echo "[ERROR] Could not parse Ninja sha256 value from manifest.json" >&2; exit 1
fi

ALL_OK=true

# ---------------------------------------------------------------------------
# LLVM
# ---------------------------------------------------------------------------
echo "[LLVM] Checking source archive..."
LLVM_ASSEMBLED="${LLVM_SRC}/${LLVM_TARBALL}"

if [[ -f "${LLVM_ASSEMBLED}" ]]; then
  echo "[MODE] Reassembled tarball found -- verifying directly."
  echo "       File: ${LLVM_ASSEMBLED}"
  ACTUAL=$(sha256sum "${LLVM_ASSEMBLED}" | awk '{print $1}')
  echo "  Expected (manifest): ${LLVM_REASSEMBLED_HASH}"
  echo "  Actual             : ${ACTUAL}"
  if [[ "${ACTUAL}" == "${LLVM_REASSEMBLED_HASH}" ]]; then
    echo "  [PASS] LLVM tarball integrity confirmed."
  else
    echo "  [FAIL] LLVM tarball hash mismatch." >&2
    ALL_OK=false
  fi
else
  echo "[MODE] No reassembled tarball -- verifying split parts."
  FOUND=0
  while IFS= read -r part_filename; do
    [[ -z "${part_filename}" ]] && continue
    part_path="${LLVM_SRC}/${part_filename}"
    expected_hash=$(get_llvm_part_hash "${part_filename}")
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
  done < <(get_llvm_part_filenames)

  if [[ "${FOUND}" -eq 0 ]]; then
    echo "  [FAIL] No LLVM parts found in llvm-src/." >&2
    ALL_OK=false
  elif [[ "${ALL_OK}" == "true" ]]; then
    echo "  [INFO] All ${FOUND} parts verified."
    echo "         Next: bash scripts/reassemble-llvm.sh"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Ninja
# ---------------------------------------------------------------------------
echo "[Ninja] Checking source tarball..."
NINJA_PATH="${NINJA_SRC}/${NINJA_TARBALL}"

if [[ ! -f "${NINJA_PATH}" ]]; then
  echo "  [FAIL] Missing: ${NINJA_PATH}" >&2
  ALL_OK=false
else
  ACTUAL=$(sha256sum "${NINJA_PATH}" | awk '{print $1}')
  echo "  Expected (manifest): ${NINJA_HASH}"
  echo "  Actual             : ${ACTUAL}"
  if [[ "${ACTUAL}" == "${NINJA_HASH}" ]]; then
    echo "  [PASS] Ninja tarball integrity confirmed."
  else
    echo "  [FAIL] Ninja tarball hash mismatch." >&2
    ALL_OK=false
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ "${ALL_OK}" == "true" ]]; then
  echo "[PASS] All source archives verified."
  exit 0
else
  echo "[FAIL] One or more source archives failed verification." >&2
  exit 1
fi