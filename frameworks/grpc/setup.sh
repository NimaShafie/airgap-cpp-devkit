#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# frameworks/grpc/setup_grpc.sh
#
# Bash entry point for the gRPC air-gap source build.
#
# PLATFORM SUPPORT:
#   Windows : Full support. Builds gRPC from source using MSVC + CMake.
#   Linux   : Not supported (requires MSVC/Windows SDK).
#
# USAGE:
#   bash frameworks/grpc/setup_grpc.sh [--version 1.76.0|1.78.1] [--prefix <path>]
#
# OPTIONS:
#   --version <ver>   gRPC version to build (default: prompts interactively)
#   --prefix <path>   Install to a custom path instead of auto-detected
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)
        echo ""
        echo "  gRPC source build — Linux not supported."
        echo "  This build requires MSVC and the Windows SDK."
        echo "  For Linux gRPC, build manually from the vendored source tarball."
        echo ""
        exit 0
        ;;
    *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

GRPC_VERSION=""
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) GRPC_VERSION="$2"; shift 2 ;;
        --prefix)  PREFIX_OVERRIDE="$2"; shift 2 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "${GRPC_VERSION}" ]]; then
    echo ""
    echo "============================================================"
    echo " gRPC Air-Gap Source Build"
    echo "============================================================"
    echo ""
    echo "  Available versions:"
    echo "    [1] gRPC v1.76.0  (production-tested)"
    echo "    [2] gRPC v1.78.1  (candidate-testing)"
    echo ""
    read -rp "  Select version (1 or 2): " VERSION_CHOICE
    case "${VERSION_CHOICE}" in
        1) GRPC_VERSION="1.76.0" ;;
        2) GRPC_VERSION="1.78.1" ;;
        *) echo "ERROR: Invalid selection." >&2; exit 1 ;;
    esac
fi

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "grpc-${GRPC_VERSION}" "${GRPC_VERSION}"
install_log_capture_start

echo ""
echo "[INFO] Selected: gRPC v${GRPC_VERSION}"
echo "[INFO] Install prefix: ${INSTALL_PREFIX}"
echo ""

DEST_WIN="$(cygpath -w "${INSTALL_PREFIX}" 2>/dev/null || \
    printf '%s' "${INSTALL_PREFIX}" | sed 's|/c/|C:\\|; s|/|\\|g')"
echo "[INFO] Windows install path: ${DEST_WIN}"
echo ""

BAT_FILE="${SCRIPT_DIR}/setup.bat"
if [[ ! -f "${BAT_FILE}" ]]; then
    echo "ERROR: setup.bat not found at ${BAT_FILE}" >&2
    exit 1
fi

BAT_WIN="$(cygpath -w "${BAT_FILE}")"

echo "[INFO] Invoking setup.bat..."
echo ""

# Check if we are already in a VS Developer environment
if command -v cl.exe &>/dev/null; then
    echo "[INFO] VS Developer environment detected (cl.exe found)."
    echo "[INFO] Running gRPC build directly..."
    echo ""
    BAT_WIN_ESC="${BAT_WIN//\//\\}"
    DEST_WIN_ESC="${DEST_WIN//\//\\}"
    echo "[INFO] Changing to grpc directory and running bat..."
    cd "${SCRIPT_DIR}"
    cmd.exe /c "setup.bat --version ${GRPC_VERSION} --dest \"${DEST_WIN}\""
    cd - > /dev/null
    BAT_EXIT=$?
else
    echo ""
    echo "  ============================================================"
    echo "  gRPC requires a Visual Studio Developer environment."
    echo "  ============================================================"
    echo ""
    echo "  Please run this script from a VS Developer Command Prompt:"
    echo ""
    echo "    1. Open: Start -> Visual Studio 2026 -> Developer Command Prompt"
    echo "    2. Run:  bash frameworks/grpc/setup.sh --version ${GRPC_VERSION}"
    echo ""
    echo "  Or run the bat file directly from VS Developer Command Prompt:"
    echo ""
    echo "    cd C:\Users\n1mz\Desktop\airgap-cpp-devkit\frameworks\grpc"
    echo "    setup.bat --version ${GRPC_VERSION} --dest ${DEST_WIN}"
    echo ""
    exit 1
fi

im_progress_stop "gRPC build complete"

if [[ "${BAT_EXIT}" -ne 0 ]]; then
    install_receipt_write "failure"
    install_mode_print_footer "failure"
    echo "ERROR: setup.bat exited with code ${BAT_EXIT}" >&2
    exit "${BAT_EXIT}"
fi

install_receipt_write "success" \
    "grpc:${INSTALL_PREFIX}" \
    "grpc_cpp_plugin:${INSTALL_PREFIX}/bin/grpc_cpp_plugin.exe"

install_env_register "${INSTALL_PREFIX}/bin"

install_mode_print_footer "success" \
    "grpc-${GRPC_VERSION}:${INSTALL_PREFIX}" \
    "grpc_cpp_plugin:${INSTALL_PREFIX}/bin/grpc_cpp_plugin.exe"