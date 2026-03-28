#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang/setup.sh
#
# Installs LLVM toolchain components for Windows 11 and RHEL 8.
#
# Components:
#   clang-linux    Slim Clang/LLVM 22.1.2 for Linux (clang, lld, llvm-ar, etc.)
#   llvm-mingw     LLVM/Clang/LLD mingw-w64 cross-compiler (Linux→Windows)
#                  or native Windows toolchain
#
# USAGE:
#   bash toolchains/clang/setup.sh [--component <all|clang|mingw>] [--prefix <path>]
#
# OPTIONS:
#   --component <all|clang|mingw>   Which component(s) to install (default: all)
#   --prefix <path>                 Override install prefix
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

VERSION="22.1.2"
MINGW_VERSION="20260324"
COMPONENT="all"
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) COMPONENT="$2"; shift 2 ;;
    --prefix)    PREFIX_OVERRIDE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  *) OS="linux" ;;
esac

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "toolchains/clang" "${VERSION}"
install_log_capture_start

echo ""
echo "============================================================"
echo " LLVM Toolchain — Setup"
echo " Clang/LLVM ${VERSION} + llvm-mingw ${MINGW_VERSION}"
echo " Platform    : ${OS}"
echo " Install mode: ${INSTALL_MODE}"
echo " Component   : ${COMPONENT}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Verify assets
# ---------------------------------------------------------------------------
im_progress_start "Verifying vendor assets"
bash "${SCRIPTS_DIR}/verify.sh" "${COMPONENT}" "${OS}"
im_progress_stop "Verification complete"
echo ""

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]]; then
  bash "${SCRIPTS_DIR}/install-linux.sh" "${COMPONENT}" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"
else
  bash "${SCRIPTS_DIR}/install-windows.sh" "${COMPONENT}" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"
fi

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
if [[ "${INSTALL_MODE}" == "admin" ]]; then
  INSTALL_BASE="/opt/airgap-cpp-devkit/toolchains/clang"
else
  if [[ "${OS}" == "windows" ]]; then
    INSTALL_BASE="${LOCALAPPDATA}/airgap-cpp-devkit/toolchains/clang"
  else
    INSTALL_BASE="${HOME}/.local/share/airgap-cpp-devkit/toolchains/clang"
  fi
fi

install_receipt_write "success" \
  "version:${VERSION}" \
  "mingw-version:${MINGW_VERSION}" \
  "component:${COMPONENT}" \
  "platform:${OS}" \
  "mode:${INSTALL_MODE}"

install_mode_print_footer "success" \
  "version:${VERSION}" \
  "install-base:${INSTALL_BASE}"

echo "  Verify:"
if [[ "${OS}" == "linux" ]]; then
  echo "    ${INSTALL_BASE}/clang/bin/clang --version"
  echo "    ${INSTALL_BASE}/llvm-mingw/bin/x86_64-w64-mingw32-clang --version"
else
  echo "    ${INSTALL_BASE}\\llvm-mingw\\bin\\clang --version"
fi
echo ""