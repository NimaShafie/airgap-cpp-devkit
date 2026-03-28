#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/7zip/setup.sh
#
# Installs 7-Zip 26.00 for Windows (Git Bash) or Linux (RHEL 8).
# Supports admin (system-wide) and user (no-root) install modes.
#
# USAGE:
#   bash dev-tools/7zip/setup.sh [--prefix <path>]
#
# OPTIONS:
#   --prefix <path>   Install to a custom path instead of auto-detected default
#
# INSTALL MODES (auto-detected via scripts/install-mode.sh):
#   admin   Windows → C:\Program Files\7-Zip\  (runs silent .exe installer)
#           Linux   → /usr/local/bin/7zz
#   user    Windows → %LOCALAPPDATA%\airgap-cpp-devkit\7zip\7za.exe  (portable)
#           Linux   → ~/.local/bin/7zz
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

VERSION="26.00"
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX_OVERRIDE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "7zip" "${VERSION}"
install_log_capture_start

# ===========================================================================
# Detect platform
# ===========================================================================
OS="linux"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac

echo ""
echo "============================================================"
echo " 7-Zip ${VERSION} — Setup"
echo " Platform    : ${OS}"
echo " Install mode: ${INSTALL_MODE}"
echo "============================================================"
echo ""

# ===========================================================================
# Verify assets
# ===========================================================================
im_progress_start "Verifying vendor assets"
bash "${SCRIPTS_DIR}/verify.sh"
im_progress_stop "Verification complete"
echo ""

# ===========================================================================
# Install
# ===========================================================================
if [[ "${OS}" == "windows" ]]; then
  bash "${SCRIPTS_DIR}/install-windows.sh" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"
else
  bash "${SCRIPTS_DIR}/install-linux.sh" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"
fi

# ===========================================================================
# Footer
# ===========================================================================
if [[ "${OS}" == "windows" ]]; then
  if [[ "${INSTALL_MODE}" == "admin" ]]; then
    INSTALLED_BIN="C:/Program Files/7-Zip/7z.exe"
  else
    INSTALLED_BIN="${LOCALAPPDATA}/airgap-cpp-devkit/7zip/7za.exe"
  fi
else
  if [[ "${INSTALL_MODE}" == "admin" ]]; then
    INSTALLED_BIN="/usr/local/bin/7zz"
  else
    INSTALLED_BIN="${HOME}/.local/bin/7zz"
  fi
fi

install_receipt_write "success" \
  "binary:${INSTALLED_BIN}" \
  "version:${VERSION}" \
  "platform:${OS}" \
  "mode:${INSTALL_MODE}"

install_mode_print_footer "success" \
  "binary:${INSTALLED_BIN}" \
  "version:${VERSION}"

echo "  Verify installation:"
if [[ "${OS}" == "windows" ]]; then
  echo "    \"${INSTALLED_BIN}\" i"
else
  echo "    7zz i"
fi
echo ""