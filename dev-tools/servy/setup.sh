#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/servy/setup.sh
#
# Installs Servy 7.3 — Windows service manager (Windows only).
# Supports admin (system-wide) and user (no-elevation) install modes.
#
# USAGE:
#   bash dev-tools/servy/setup.sh [--prefix <path>]
#
# OPTIONS:
#   --prefix <path>   Install to a custom path instead of auto-detected default
#
# INSTALL MODES (auto-detected via scripts/install-mode.sh):
#   admin   C:\Program Files\servy\
#   user    %LOCALAPPDATA%\airgap-cpp-devkit\servy\
#
# NOTE: Servy is a Windows-only tool. Running this script on Linux will
#       print an informational message and exit cleanly.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

VERSION="7.3"
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX_OVERRIDE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Linux guard — Servy is Windows-only
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  *)
    echo ""
    echo "  [--] Servy ${VERSION} is a Windows-only tool."
    echo "       Skipping installation on this platform."
    echo ""
    exit 0
    ;;
esac

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "servy" "${VERSION}"
install_log_capture_start

echo ""
echo "============================================================"
echo " Servy ${VERSION} — Setup"
echo " Windows service manager (portable, self-contained)"
echo " Install mode: ${INSTALL_MODE}"
echo "============================================================"
echo ""

# Step 1: Verify parts
im_progress_start "Verifying vendor parts"
bash "${SCRIPTS_DIR}/verify.sh"
im_progress_stop "Verification complete"
echo ""

# Step 2: Install
im_progress_start "Installing Servy ${VERSION}"
bash "${SCRIPTS_DIR}/install-windows.sh" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"
im_progress_stop "Installation complete"

# ---------------------------------------------------------------------------
# Determine installed binary paths for receipt
# ---------------------------------------------------------------------------
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}"
elif [[ "${INSTALL_MODE}" == "admin" ]]; then
  INSTALL_DIR="/c/Program Files/servy"
else
  INSTALL_DIR="${LOCALAPPDATA}/airgap-cpp-devkit/servy"
fi

CLI_BIN="${INSTALL_DIR}/servy-cli.exe"

install_receipt_write "success" \
  "cli:${CLI_BIN}" \
  "version:${VERSION}" \
  "mode:${INSTALL_MODE}"

install_mode_print_footer "success" \
  "cli:${CLI_BIN}" \
  "version:${VERSION}"

echo "  Verify installation:"
echo "    servy-cli.exe --version --quiet"
echo ""
echo "  Quick start:"
echo "    servy-cli.exe install --name=\"MyApp\" --path=\"C:\\MyApp\\MyApp.exe\" --startupType=\"Automatic\""
echo "    servy-cli.exe start --name=\"MyApp\""
echo ""