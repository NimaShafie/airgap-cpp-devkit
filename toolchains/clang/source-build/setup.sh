#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang/source-build/setup.sh
#
# Installs clang-format and clang-tidy from vendored binaries.
#
# Windows: uses vendored pre-built binaries — no compiler required.
# Linux:   uses pre-built binaries; requires gcc-toolset-15 for libstdc++.
#          Build from source with --build-from-source if needed.
#
# USAGE:
#   bash toolchains/clang/source-build/setup.sh [--rebuild] [--build-from-source] [--prefix <path>]
#
# OPTIONS:
#   --rebuild            Force re-verify/rebuild of all binaries
#   --build-from-source  Build both tools from LLVM source (Linux only, ~30-60 min)
#   --prefix <path>      Install to a custom path instead of auto-detected
# =============================================================================

set -euo pipefail

REBUILD=false
BUILD_FROM_SOURCE=false
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild)           REBUILD=true; shift ;;
        --build-from-source) BUILD_FROM_SOURCE=true; shift ;;
        --prefix)            PREFIX_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMATTER_DIR="$(cd "${SCRIPT_DIR}/../style-formatter" 2>/dev/null && pwd)" || \
    FORMATTER_DIR="${SCRIPT_DIR}/../style-formatter"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)                OS="linux"   ;;
    *)  echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/clang/source-build"

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "toolchains/clang/source-build" "22.1.2"
install_log_capture_start

# ---------------------------------------------------------------------------
# On Linux: set LD_LIBRARY_PATH to gcc-toolset-15 libstdc++ so binaries run
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]]; then
    GCC15_LIBDIR="$(find /opt/rh/gcc-toolset-15 -name 'libstdc++.so*' 2>/dev/null \
        | grep -v '/32' | xargs -I{} dirname {} 2>/dev/null | head -1 || true)"
    if [[ -n "${GCC15_LIBDIR}" ]]; then
        export LD_LIBRARY_PATH="${GCC15_LIBDIR}:${LD_LIBRARY_PATH:-}"
        echo "[setup] LD_LIBRARY_PATH set to gcc-toolset-15 libstdc++: ${GCC15_LIBDIR}"
    else
        echo "[setup] WARNING: gcc-toolset-15 not found. clang-format/tidy may fail to run."
        echo "[setup]          Install gcc-toolset-15 first: bash toolchains/gcc/linux/native/setup.sh"
    fi
fi

OUTPUT_FMT_WIN="${PREBUILT_DIR}/clang-format.exe"
OUTPUT_TIDY_WIN="${PREBUILT_DIR}/clang-tidy.exe"
OUTPUT_FMT_LIN="${PREBUILT_DIR}/clang-format-linux"
OUTPUT_TIDY_LIN="${SCRIPT_DIR}/bin/linux/clang-tidy"

case "${OS}" in
    windows) OUTPUT_FMT="${OUTPUT_FMT_WIN}"; OUTPUT_TIDY="${OUTPUT_TIDY_WIN}" ;;
    linux)   OUTPUT_FMT="${OUTPUT_FMT_LIN}"; OUTPUT_TIDY="${OUTPUT_TIDY_LIN}" ;;
esac

echo "=================================================================="
echo "  toolchains/clang/source-build"
echo "  Platform     : ${OS}"
echo "  clang-format : ${OUTPUT_FMT}"
echo "  clang-tidy   : ${OUTPUT_TIDY}"
echo "=================================================================="
echo ""

# ==========================================================================
# PART 1 — clang-format
# ==========================================================================
echo "------------------------------------------------------------------"
echo "  [1/2] clang-format"
echo "------------------------------------------------------------------"
echo ""

if [[ -x "${OUTPUT_FMT}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_FMT}" --version 2>/dev/null | head -1)" || VER="(run --version failed, may need LD_LIBRARY_PATH)"
    echo "  Already present: ${VER}"
    echo "  Use --rebuild to force re-verification."
else
    case "${OS}" in
        windows)
            if [[ "${BUILD_FROM_SOURCE}" == "true" ]]; then
                echo "  Windows: building from source (~30-60 min)..."
                im_progress_start "Building clang-format from source"
                export REBUILD
                bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"
                im_progress_stop "clang-format build complete"
            else
                echo "  Windows: verifying vendored pre-built binary..."
                im_progress_start "Verifying clang-format.exe"
                bash "${SCRIPT_DIR}/scripts/verify-clang-format-windows.sh"
                im_progress_stop "clang-format verified"
            fi
            ;;
        linux)
            if [[ "${BUILD_FROM_SOURCE}" == "true" ]]; then
                echo "  Linux: building from source (~30-60 min)..."
                im_progress_start "Building clang-format from source"
                export REBUILD
                bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"
                im_progress_stop "clang-format build complete"
            else
                echo "  Linux: verifying vendored pre-built binary..."
                im_progress_start "Verifying clang-format-linux"
                bash "${SCRIPT_DIR}/scripts/verify-clang-format-linux.sh"
                im_progress_stop "clang-format verified"
            fi
            ;;
    esac

    [[ -x "${OUTPUT_FMT}" ]] || {
        echo "ERROR: clang-format not found at ${OUTPUT_FMT}" >&2
        exit 1
    }
    VER="$("${OUTPUT_FMT}" --version 2>/dev/null | head -1)" || VER="(binary present but requires gcc-toolset-15 libstdc++)"
    echo "  Ready: ${VER}"
fi

echo ""

# ==========================================================================
# PART 2 — clang-tidy
# ==========================================================================
echo "------------------------------------------------------------------"
echo "  [2/2] clang-tidy"
echo "------------------------------------------------------------------"
echo ""

if [[ -x "${OUTPUT_TIDY}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | grep "LLVM version" | head -1)" || VER="(run --version failed)"
    echo "  Already present: ${VER}"
    echo "  Use --rebuild to force re-verification."
else
    case "${OS}" in
        linux)
            echo "  Linux: reassembling from vendored pre-built parts..."
            im_progress_start "Reassembling clang-tidy from split parts"
            bash "${SCRIPT_DIR}/scripts/reassemble-clang-tidy.sh"
            im_progress_stop "clang-tidy reassembled"

            [[ -x "${OUTPUT_TIDY}" ]] || {
                echo "ERROR: clang-tidy not found at ${OUTPUT_TIDY} after reassembly." >&2
                exit 1
            }
            ;;
        windows)
            if [[ "${BUILD_FROM_SOURCE}" == "true" ]]; then
                echo "  Windows: building from source (~60-120 min)..."
                im_progress_start "Building clang-tidy from source"
                bash "${SCRIPT_DIR}/scripts/build-clang-tidy.sh" \
                    $([[ "${REBUILD}" == "true" ]] && echo "--rebuild" || true)
                im_progress_stop "clang-tidy build complete"
            else
                echo "  Windows: verifying vendored pre-built binary..."
                im_progress_start "Verifying clang-tidy.exe"
                bash "${SCRIPT_DIR}/scripts/verify-clang-tidy-windows.sh"
                im_progress_stop "clang-tidy verified"
            fi

            [[ -x "${OUTPUT_TIDY}" ]] || {
                echo "ERROR: clang-tidy not found at ${OUTPUT_TIDY}." >&2
                exit 1
            }
            ;;
    esac

    VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | grep "LLVM version" | head -1)" || VER="(binary present but requires gcc-toolset-15 libstdc++)"
    echo "  Ready: ${VER}"
fi

echo ""

# ==========================================================================
# Install binaries to system/user path
# ==========================================================================
im_progress_start "Installing binaries to ${INSTALL_BIN_DIR}"
mkdir -p "${INSTALL_BIN_DIR}"

_install_bin() {
    local src="$1" name="$2"
    if [[ -x "${src}" ]]; then
        cp -f "${src}" "${INSTALL_BIN_DIR}/${name}"
        chmod +x "${INSTALL_BIN_DIR}/${name}"
    fi
}

case "${OS}" in
    windows)
        _install_bin "${OUTPUT_FMT}"  "clang-format.exe"
        _install_bin "${OUTPUT_TIDY}" "clang-tidy.exe"
        ;;
    linux)
        _install_bin "${OUTPUT_FMT}"  "clang-format"
        _install_bin "${OUTPUT_TIDY}" "clang-tidy"

        # Write env-setup.sh so users can source LD_LIBRARY_PATH automatically
        ENV_SETUP="${INSTALL_BIN_DIR}/../env-setup.sh"
        cat > "${ENV_SETUP}" << 'ENVEOF'
#!/usr/bin/env bash
# Source this file to activate clang-format and clang-tidy on RHEL 8.
# Sets LD_LIBRARY_PATH to gcc-toolset-15 libstdc++ so binaries can run.
GCC15_LIBDIR="$(find /opt/rh/gcc-toolset-15 -name 'libstdc++.so*' 2>/dev/null \
    | grep -v '/32' | xargs -I{} dirname {} 2>/dev/null | head -1 || true)"
if [[ -n "${GCC15_LIBDIR}" ]]; then
    export LD_LIBRARY_PATH="${GCC15_LIBDIR}:${LD_LIBRARY_PATH:-}"
fi
ENVEOF
        chmod +x "${ENV_SETUP}"
        echo "[setup] env-setup.sh written: source ${ENV_SETUP}"
        ;;
esac
im_progress_stop "Binaries installed"

install_receipt_write "success" \
    "clang-format:${INSTALL_BIN_DIR}/clang-format" \
    "clang-tidy:${INSTALL_BIN_DIR}/clang-tidy"

install_env_register "${INSTALL_BIN_DIR}"

install_mode_print_footer "success" \
    "clang-format:${INSTALL_BIN_DIR}/clang-format" \
    "clang-tidy:${INSTALL_BIN_DIR}/clang-tidy"

if [[ "${OS}" == "linux" ]]; then
    echo "  IMPORTANT: Add to ~/.bashrc for permanent activation:"
    echo "    source /opt/rh/gcc-toolset-15/enable"
    echo "    LIBDIR=\$(find /opt/rh/gcc-toolset-15 -name 'libstdc++.so*' | grep -v /32 | xargs dirname | head -1)"
    echo "    export LD_LIBRARY_PATH=\"\${LIBDIR}:\${LD_LIBRARY_PATH:-}\""
fi
echo ""
echo "  Now activate the pre-commit hook:"
echo "    bash ${FORMATTER_DIR}/setup.sh"
echo ""