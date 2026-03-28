#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/gcc/windows/setup.sh
#
# Single entry point for the WinLibs GCC UCRT toolchain.
# Verifies, reassembles, and installs in one step.
#
# USAGE:
#   bash toolchains/gcc/windows/setup.sh [x86_64|i686] [--prefix <path>]
#
# OPTIONS:
#   --prefix <path>   Install to a custom path instead of auto-detected
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS="${SCRIPT_DIR}/scripts"
ARCH="${1:-x86_64}"
PREFIX_OVERRIDE=""

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX_OVERRIDE="$2"; shift 2 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
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

# Step 1: Verify parts
im_progress_start "Verifying vendor parts"
bash "${SCRIPTS}/verify.sh" "${ARCH}"
im_progress_stop "Verification complete"

echo ""

# Step 2: Reassemble
im_progress_start "Reassembling archive (this may take a moment)"
bash "${SCRIPTS}/reassemble.sh" "${ARCH}"
im_progress_stop "Archive reassembled"

echo ""

# Step 3: Install
im_progress_start "Installing to ${INSTALL_DIR}"
bash "${SCRIPTS}/install.sh" "${ARCH}" "${INSTALL_DIR}"
im_progress_stop "Installation complete"

GCC_BIN="${INSTALL_DIR}/mingw64/bin/gcc.exe"
[[ "${ARCH}" == "i686" ]] && GCC_BIN="${INSTALL_DIR}/mingw32/bin/gcc.exe"

install_receipt_write "success" \
    "gcc:${GCC_BIN}" \
    "install-dir:${INSTALL_DIR}"

install_env_register "${INSTALL_DIR}/mingw64/bin"

install_mode_print_footer "success" \
    "gcc:${GCC_BIN}" \
    "install-dir:${INSTALL_DIR}"

echo "  Activate in your current shell:"
echo "    source ${SCRIPT_DIR}/scripts/env-setup.sh ${ARCH} ${INSTALL_DIR}"
echo ""