#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/setup.sh
#
# Single entry point for the WinLibs GCC UCRT toolchain.
# Verifies, reassembles, and installs in one step.
#
# USAGE:
#   bash setup.sh [x86_64|i686]     # default: x86_64
#
# INSTALL MODES:
#   Admin (system-wide) : C:\Program Files\airgap-cpp-devkit\winlibs\<arch>\
#   User  (per-user)    : %LOCALAPPDATA%\airgap-cpp-devkit\winlibs\<arch>\
#
#   Admin mode is attempted first. If the current user cannot write to
#   Program Files, user mode is used automatically with a clear warning.
#
# After setup completes, activate in your current shell with:
#   source scripts/env-setup.sh [x86_64|i686]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS="${SCRIPT_DIR}/scripts"
ARCH="${1:-x86_64}"

# ---------------------------------------------------------------------------
# Source shared install-mode library
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "winlibs-gcc-ucrt" "15.2.0"
install_log_capture_start

INSTALL_DIR="${INSTALL_PREFIX}/${ARCH}"

echo ""
echo "============================================================"
echo " WinLibs GCC UCRT — Setup"
echo " GCC 15.2.0 + MinGW-w64 13.0.0 UCRT (r6)"
echo " Arch        : ${ARCH}"
echo " Install dir : ${INSTALL_DIR}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify parts (from prebuilt-binaries submodule)
# ---------------------------------------------------------------------------
echo ">>> [1/3] Verifying vendor parts..."
bash "${SCRIPTS}/verify.sh" "${ARCH}"

# ---------------------------------------------------------------------------
# Step 2: Reassemble
# ---------------------------------------------------------------------------
echo ""
echo ">>> [2/3] Reassembling archive..."
bash "${SCRIPTS}/reassemble.sh" "${ARCH}"

# ---------------------------------------------------------------------------
# Step 3: Install
# ---------------------------------------------------------------------------
echo ""
echo ">>> [3/3] Installing to ${INSTALL_DIR}..."
bash "${SCRIPTS}/install.sh" "${ARCH}" "${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Write install receipt
# ---------------------------------------------------------------------------
GCC_BIN="${INSTALL_DIR}/mingw64/bin/gcc.exe"
[[ "${ARCH}" == "i686" ]] && GCC_BIN="${INSTALL_DIR}/mingw32/bin/gcc.exe"

install_receipt_write "success" \
    "gcc:${GCC_BIN}" \
    "install-dir:${INSTALL_DIR}"

install_mode_print_footer "success" \
    "gcc:${GCC_BIN}" \
    "install-dir:${INSTALL_DIR}"

echo ""
echo "  Activate in your current shell:"
echo "    source ${SCRIPT_DIR}/scripts/env-setup.sh ${ARCH} ${INSTALL_DIR}"
echo ""
