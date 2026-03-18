#!/usr/bin/env bash
# =============================================================================
# grpc-source-build/setup.sh
#
# PURPOSE: Single entry point for the gRPC source tree.
#          Verifies, reassembles, and extracts the vendored source archive
#          back to its original directory structure.
#
# USAGE:
#   bash setup.sh [extract_dir]
#
#   extract_dir defaults to: <module_root>/src/
#   Final path will be:      <extract_dir>/grpc_unbuilt_v1.76.0/
#
# EXAMPLE:
#   bash setup.sh                          # extracts to grpc-source-build/src/
#   bash setup.sh /c/Users/Public/FTE_Software   # extracts to that path
#
# AFTER SETUP:
#   Windows: run setup_grpc.bat from Developer PowerShell for VS 2022
#   See README.md for full build instructions.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${SCRIPT_DIR}/scripts"
MANIFEST="${SCRIPT_DIR}/manifest.json"
VENDOR_DIR="${SCRIPT_DIR}/vendor"

# Default extract destination
EXTRACT_DIR="${1:-${SCRIPT_DIR}/src}"

# Parse extract_root from manifest
EXTRACT_ROOT=$(grep '"extract_root"' "${MANIFEST}" | head -1 \
  | sed 's/.*"extract_root": *"\([^"]*\)".*/\1/' || true)

TARBALL=$(grep '"tarball_filename"' "${MANIFEST}" | head -1 \
  | sed 's/.*"tarball_filename": *"\([^"]*\)".*/\1/' || true)

TARBALL_PATH="${VENDOR_DIR}/${TARBALL}"
FINAL_PATH="${EXTRACT_DIR}/${EXTRACT_ROOT}"

echo ""
echo "============================================================"
echo " grpc-source-build -- Setup"
echo " gRPC v1.76.0 source tree"
echo " Extract to: ${FINAL_PATH}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify parts
# ---------------------------------------------------------------------------
echo ">>> [1/3] Verifying vendor parts..."
echo ""
if ! bash "${SCRIPTS}/verify.sh"; then
  echo "" >&2
  echo "[ABORT] Verification failed. Setup cancelled." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Reassemble (if tarball not already present)
# ---------------------------------------------------------------------------
if [[ ! -f "${TARBALL_PATH}" ]]; then
  echo ">>> [2/3] Reassembling archive..."
  echo ""
  if ! bash "${SCRIPTS}/reassemble.sh"; then
    echo "" >&2
    echo "[ABORT] Reassembly failed. Setup cancelled." >&2
    exit 1
  fi
else
  echo ">>> [2/3] Tarball already present -- skipping reassembly."
  echo "          ${TARBALL_PATH}"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Extract
# ---------------------------------------------------------------------------
echo ">>> [3/3] Extracting source tree..."
echo ""

mkdir -p "${EXTRACT_DIR}"

# Remove previous extraction if present
if [[ -d "${FINAL_PATH}" ]]; then
  echo "[INFO] Removing previous extraction at ${FINAL_PATH}..."
  rm -rf "${FINAL_PATH}"
fi

echo "[INFO] Extracting ${TARBALL} to ${EXTRACT_DIR}..."
tar -xzf "${TARBALL_PATH}" -C "${EXTRACT_DIR}"

# Verify extraction root exists
if [[ ! -d "${FINAL_PATH}" ]]; then
  echo "[ERROR] Expected extraction root not found: ${FINAL_PATH}" >&2
  echo "        Check manifest extract_root field." >&2
  exit 1
fi

# Quick sanity check — verify CMakeLists.txt is present
if [[ ! -f "${FINAL_PATH}/CMakeLists.txt" ]]; then
  echo "[WARN] CMakeLists.txt not found in extracted tree." >&2
  echo "       Archive may be corrupt or layout has changed." >&2
else
  echo "[PASS] CMakeLists.txt found -- source tree looks correct."
fi

echo ""
echo "============================================================"
echo " [SUCCESS] gRPC source tree extracted."
echo ""
echo " Location: ${FINAL_PATH}"
echo " Files   : $(find "${FINAL_PATH}" | wc -l) items"
echo ""
echo " Next step (Windows):"
echo "   Open Developer PowerShell for VS 2022"
echo "   cd to the directory containing setup_grpc.bat"
echo "   .\\setup_grpc.bat"
echo ""
echo " Or follow manual CMake steps in README.md."
echo "============================================================"
echo ""
