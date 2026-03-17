#!/usr/bin/env bash
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/setup.sh
#
# Single entry point for the WinLibs GCC UCRT toolchain.
# Verifies, reassembles, and installs in one step.
#
# USAGE:
#   bash setup.sh [x86_64|i686]     # default: x86_64
#
# WHAT IT DOES:
#   1. Verifies all split parts against pinned SHA256 hashes
#   2. Reassembles parts into the original .7z and verifies the archive
#   3. Extracts the toolchain and runs a smoke test
#   4. Prints the source command to activate the toolchain
#
# After setup completes, activate in your current shell with:
#   source scripts/env-setup.sh [x86_64|i686]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${SCRIPT_DIR}/scripts"

ARCH="${1:-x86_64}"

echo ""
echo "============================================================"
echo " WinLibs GCC UCRT — Setup"
echo " GCC 15.2.0 + MinGW-w64 13.0.0 UCRT (r6)"
echo " Arch: ${ARCH}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify parts
# ---------------------------------------------------------------------------
echo ">>> [1/3] Verifying vendor parts..."
echo ""
if ! bash "${SCRIPTS}/verify.sh" "${ARCH}"; then
  echo "" >&2
  echo "[ABORT] Part verification failed. Setup cancelled." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Reassemble
# ---------------------------------------------------------------------------
echo ">>> [2/3] Reassembling and verifying archive..."
echo ""
if ! bash "${SCRIPTS}/reassemble.sh" "${ARCH}"; then
  echo "" >&2
  echo "[ABORT] Reassembly failed. Setup cancelled." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Install
# ---------------------------------------------------------------------------
echo ">>> [3/3] Installing toolchain..."
echo ""
if ! bash "${SCRIPTS}/install.sh" "${ARCH}"; then
  echo "" >&2
  echo "[ABORT] Installation failed." >&2
  exit 1
fi

echo ""
echo "============================================================"
echo " Setup complete."
echo ""
echo " Activate this toolchain in your current shell:"
echo "   source \"${SCRIPT_DIR}/scripts/env-setup.sh\" ${ARCH}"
echo ""
echo " Or add to ~/.bashrc for permanent activation:"
echo "   echo \"source '${SCRIPT_DIR}/scripts/env-setup.sh' ${ARCH}\" >> ~/.bashrc"
echo "============================================================"
echo ""