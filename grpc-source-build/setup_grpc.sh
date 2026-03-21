#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# grpc-source-build/setup_grpc.sh
#
# Bash entry point for the gRPC air-gap source build.
# Replaces setup_grpc.bat as the primary entry point for consistency
# with the rest of airgap-cpp-devkit.
#
# PLATFORM SUPPORT:
#   Windows : Full support. Builds gRPC from source using MSVC + CMake.
#             Requires: Git Bash, Visual Studio 2022 Insiders (C++ workload)
#   Linux   : Not supported. gRPC requires MSVC/Windows SDK for this build.
#             For Linux gRPC, build manually from the vendored source tarball.
#
# INSTALL MODES:
#   Admin (system-wide) : C:\Program Files\airgap-cpp-devkit\grpc-<ver>\
#   User  (per-user)    : %LOCALAPPDATA%\airgap-cpp-devkit\grpc-<ver>\
#
#   Admin mode is attempted first. Falls back to user mode automatically
#   with a clear warning if admin rights are not available.
#
# USAGE:
#   bash grpc-source-build/setup_grpc.sh [--version 1.76.0|1.78.1]
#
# Options:
#   --version  gRPC version to build (default: prompts interactively)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Platform check
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║  gRPC source build — Linux not supported                         ║"
        echo "╠══════════════════════════════════════════════════════════════════╣"
        echo "║                                                                  ║"
        echo "║  This gRPC build requires MSVC and the Windows SDK.             ║"
        echo "║  It is only supported on Windows with Visual Studio installed.  ║"
        echo "║                                                                  ║"
        echo "║  For Linux gRPC:                                                 ║"
        echo "║    Build manually from the vendored source tarball in            ║"
        echo "║    grpc-source-build/vendor/ using GCC + CMake.                 ║"
        echo "║                                                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        exit 0
        ;;
    *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Version selection
# ---------------------------------------------------------------------------
GRPC_VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) GRPC_VERSION="$2"; shift 2 ;;
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

# ---------------------------------------------------------------------------
# Source shared install-mode library
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "grpc-${GRPC_VERSION}" "${GRPC_VERSION}"
install_log_capture_start

echo ""
echo "[INFO] Selected: gRPC v${GRPC_VERSION}"
echo "[INFO] Install prefix: ${INSTALL_PREFIX}"
echo ""

# ---------------------------------------------------------------------------
# Convert install prefix to Windows path for the bat file
# ---------------------------------------------------------------------------
DEST_WIN="$(cygpath -w "${INSTALL_PREFIX}" 2>/dev/null || \
    printf '%s' "${INSTALL_PREFIX}" | sed 's|/c/|C:\\|; s|/|\\|g')"

echo "[INFO] Windows install path: ${DEST_WIN}"
echo ""

# ---------------------------------------------------------------------------
# Check for bash.exe and bat file
# ---------------------------------------------------------------------------
BAT_FILE="${SCRIPT_DIR}/setup_grpc.bat"
if [[ ! -f "${BAT_FILE}" ]]; then
    echo "ERROR: setup_grpc.bat not found at ${BAT_FILE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Delegate to setup_grpc.bat, passing install path and version
# Converts to Windows cmd.exe path for the bat invocation
# ---------------------------------------------------------------------------
echo "[INFO] Invoking setup_grpc.bat..."
echo ""

BAT_WIN="$(cygpath -w "${BAT_FILE}")"

cmd.exe /c "\"${BAT_WIN}\" --dest \"${DEST_WIN}\" --version \"${GRPC_VERSION}\""
BAT_EXIT=$?

if [[ "${BAT_EXIT}" -ne 0 ]]; then
    install_receipt_write "failure"
    install_mode_print_footer "failure"
    echo "ERROR: setup_grpc.bat exited with code ${BAT_EXIT}" >&2
    exit "${BAT_EXIT}"
fi

# ---------------------------------------------------------------------------
# Write receipt and footer
# ---------------------------------------------------------------------------
install_receipt_write "success" \
    "grpc:${INSTALL_PREFIX}" \
    "grpc_cpp_plugin:${INSTALL_PREFIX}/bin/grpc_cpp_plugin.exe"

install_mode_print_footer "success" \
    "grpc-${GRPC_VERSION}:${INSTALL_PREFIX}" \
    "grpc_cpp_plugin:${INSTALL_PREFIX}/bin/grpc_cpp_plugin.exe"
