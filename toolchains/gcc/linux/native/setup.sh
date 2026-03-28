#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/gcc/linux/native/setup.sh
#
# Installs toolchains/gcc/linux/native-15 on RHEL 8 / Rocky Linux 8 from vendored RPMs.
# Provides GCC 15.1.1, G++, libstdc++ with GLIBCXX_3.4.30+, binutils 2.44.
#
# Linux only — no Windows component.
#
# USAGE:
#   bash toolchains/gcc/linux/native/setup.sh [--prefix <path>]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

VERSION="15.1.1"
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX_OVERRIDE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Linux only
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "[toolchains/gcc/linux/native] This module is Linux-only. Skipping on Windows."
    exit 0
    ;;
esac

# Verify RHEL/Rocky 8
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  if [[ "${VERSION_ID}" != "8"* ]]; then
    echo "WARNING: This module targets RHEL/Rocky 8. Detected: ${PRETTY_NAME}" >&2
    echo "         Proceeding anyway — RPM install may fail on other distros." >&2
  fi
fi

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "toolchains/gcc/linux/native" "${VERSION}"
install_log_capture_start

echo ""
echo "============================================================"
echo " toolchains/gcc/linux/native-15 — Setup"
echo " GCC/G++ ${VERSION} for RHEL 8"
echo " Install mode: ${INSTALL_MODE}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
im_progress_start "Verifying vendor assets"
bash "${SCRIPTS_DIR}/verify.sh"
im_progress_stop "Verification complete"
echo ""

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
bash "${SCRIPTS_DIR}/install-linux.sh" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
install_receipt_write "success" \
  "version:${VERSION}" \
  "mode:${INSTALL_MODE}"

install_mode_print_footer "success" \
  "version:${VERSION}" \
  "install-base:/opt/rh/toolchains/gcc/linux/native-15"

echo "  Activate in current shell:"
echo "    source /opt/rh/toolchains/gcc/linux/native-15/enable"
echo ""
echo "  Or add to ~/.bashrc for persistent activation:"
echo "    echo 'source /opt/rh/toolchains/gcc/linux/native-15/enable' >> ~/.bashrc"
echo ""