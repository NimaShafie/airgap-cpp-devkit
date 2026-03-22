#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# install.sh
#
# Top-level orchestrator for airgap-cpp-devkit.
# Installs all tools in the correct order and wires PATH into ~/.bashrc.
#
# REQUIRED tools (installed automatically):
#   - clang-llvm  (clang-format + clang-tidy)
#   - cmake       4.3.0
#   - lcov        2.4  (Linux only)
#   - style-formatter  (pre-commit hook)
#
# OPTIONAL tools (prompted):
#   - winlibs-gcc-ucrt  (Windows only)
#   - grpc-source-build (Windows only)
#
# USAGE:
#   bash install.sh [--prefix <path>] [--rebuild] [--yes]
#
# OPTIONS:
#   --prefix <path>   Override install prefix for all tools
#   --rebuild         Force reinstall of all tools
#   --yes             Auto-accept all optional tool prompts (non-interactive)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PREFIX_OVERRIDE=""
REBUILD=false
AUTO_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  PREFIX_OVERRIDE="$2"; shift 2 ;;
        --rebuild) REBUILD=true; shift ;;
        --yes)     AUTO_YES=true; shift ;;
        -h|--help)
            sed -n '2,/^[^#]/{/^#/!q; s/^# \?//; p}' "$0"
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)                OS="linux"   ;;
    *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Source install-mode for box printing helpers only (no init)
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_box_top() {
    local l=""; local i; for((i=0;i<98;i++)); do l+="═"; done
    printf '╔%s╗\n' "${l}"
}
_box_mid() {
    local l=""; local i; for((i=0;i<98;i++)); do l+="═"; done
    printf '╠%s╣\n' "${l}"
}
_box_bot() {
    local l=""; local i; for((i=0;i<98;i++)); do l+="═"; done
    printf '╚%s╝\n' "${l}"
}
_box_line() {
    local str="$1" width=98
    if (( ${#str} > width )); then str="${str:0:$(( width - 3 ))}..."; fi
    local pad=$(( width - ${#str} ))
    printf '║%s%*s║\n' "${str}" "${pad}" ""
}

_prompt_optional() {
    local tool="$1" hint="$2"
    if [[ "${AUTO_YES}" == "true" ]]; then
        echo "  [--yes] Auto-installing optional tool: ${tool}"
        return 0
    fi
    echo ""
    printf "  Install optional tool: %s? [y/N] " "${tool}"
    printf "  (%s)\n" "${hint}"
    read -r reply
    [[ "${reply}" =~ ^[Yy]$ ]]
}

_run_bootstrap() {
    local label="$1"
    local script="$2"
    shift 2
    local extra_args=("$@")

    echo ""
    echo "  ── ${label} ──────────────────────────────────────────────────────"

    local prefix_arg=()
    [[ -n "${PREFIX_OVERRIDE}" ]] && prefix_arg=("--prefix" "${PREFIX_OVERRIDE}")

    local rebuild_arg=()
    [[ "${REBUILD}" == "true" ]] && rebuild_arg=("--rebuild")

    if bash "${script}" "${prefix_arg[@]}" "${rebuild_arg[@]}" "${extra_args[@]}"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} installation FAILED — continuing with remaining tools."
    fi
}

INSTALLED_TOOLS=()
FAILED_TOOLS=()
SKIPPED_TOOLS=()

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
_box_top
_box_line "  airgap-cpp-devkit — Full Installation"
_box_mid
_box_line "  Platform : ${OS}"
_box_line "  Date     : $(date '+%Y-%m-%d %H:%M:%S')"
[[ -n "${PREFIX_OVERRIDE}" ]] && _box_line "  Prefix   : ${PREFIX_OVERRIDE} (override)"
_box_line "  Rebuild  : ${REBUILD}"
_box_bot
echo ""

# ---------------------------------------------------------------------------
# Check prebuilt-binaries submodule
# ---------------------------------------------------------------------------
echo "  [1/6] Checking prebuilt-binaries submodule..."
if [[ ! -f "${REPO_ROOT}/prebuilt-binaries/.git" ]] && \
   ! git -C "${REPO_ROOT}" submodule status prebuilt-binaries 2>/dev/null | grep -q "^[^-]"; then
    im_progress_start "Initialising prebuilt-binaries submodule"
    git -C "${REPO_ROOT}" submodule update --init --recursive prebuilt-binaries
    im_progress_stop "Submodule ready"
else
    echo "  [OK]  prebuilt-binaries submodule already initialized."
fi

# ---------------------------------------------------------------------------
# REQUIRED: clang-llvm
# ---------------------------------------------------------------------------
echo ""
echo "  [2/6] Installing clang-llvm (required)..."
_run_bootstrap "clang-llvm" \
    "${REPO_ROOT}/clang-llvm/source-build/bootstrap.sh"

# ---------------------------------------------------------------------------
# REQUIRED: cmake
# ---------------------------------------------------------------------------
echo ""
echo "  [3/6] Installing cmake (required)..."
_run_bootstrap "cmake" \
    "${REPO_ROOT}/cmake/bootstrap.sh"

# ---------------------------------------------------------------------------
# REQUIRED (Linux only): lcov
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]]; then
    echo ""
    echo "  [4/6] Installing lcov (required on Linux)..."
    _run_bootstrap "lcov" \
        "${REPO_ROOT}/lcov-source-build/bootstrap.sh"
else
    echo ""
    echo "  [4/6] lcov — skipped (Linux only)"
    SKIPPED_TOOLS+=("lcov (Linux only)")
fi

# ---------------------------------------------------------------------------
# REQUIRED: style-formatter
# ---------------------------------------------------------------------------
echo ""
echo "  [5/6] Installing style-formatter (required)..."
_run_bootstrap "style-formatter" \
    "${REPO_ROOT}/clang-llvm/style-formatter/bootstrap.sh"

# ---------------------------------------------------------------------------
# OPTIONAL: winlibs-gcc-ucrt (Windows only)
# ---------------------------------------------------------------------------
echo ""
echo "  [6/6] Optional tools..."
if [[ "${OS}" == "windows" ]]; then
    if _prompt_optional "winlibs-gcc-ucrt" \
        "WinLibs GCC 15.2.0 + MinGW-w64 — required for C++ source builds on Windows"; then
        _run_bootstrap "winlibs-gcc-ucrt" \
            "${REPO_ROOT}/prebuilt/winlibs-gcc-ucrt/setup.sh"
    else
        echo "  [--]  Skipped: winlibs-gcc-ucrt"
        SKIPPED_TOOLS+=("winlibs-gcc-ucrt")
    fi

    if _prompt_optional "grpc-source-build" \
        "gRPC v1.76.0/v1.78.1 — required for gRPC C++ development"; then
        _run_bootstrap "grpc-source-build" \
            "${REPO_ROOT}/grpc-source-build/setup_grpc.sh"
    else
        echo "  [--]  Skipped: grpc-source-build"
        SKIPPED_TOOLS+=("grpc-source-build")
    fi
else
    echo "  [--]  winlibs-gcc-ucrt  — skipped (Windows only)"
    echo "  [--]  grpc-source-build — skipped (Windows only)"
    SKIPPED_TOOLS+=("winlibs-gcc-ucrt (Windows only)" "grpc-source-build (Windows only)")
fi

# ---------------------------------------------------------------------------
# Wire env.sh into ~/.bashrc
# ---------------------------------------------------------------------------
echo ""
echo "  Wiring env.sh into ~/.bashrc..."

# Determine env.sh path — one level above tool install prefix
# Source install-mode just for the prefix resolution
source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "cmake" "4.3.0" 2>/dev/null || true

ENV_DIR="$(dirname "${INSTALL_PREFIX}")"
ENV_FILE="${ENV_DIR}/env.sh"
BASHRC="${HOME}/.bashrc"

if [[ -f "${ENV_FILE}" ]]; then
    SOURCE_LINE="source \"${ENV_FILE}\""
    if grep -qF "${ENV_FILE}" "${BASHRC}" 2>/dev/null; then
        echo "  [OK]  env.sh already wired into ${BASHRC}"
    else
        echo "" >> "${BASHRC}"
        echo "# airgap-cpp-devkit — added by install.sh" >> "${BASHRC}"
        echo "${SOURCE_LINE}" >> "${BASHRC}"
        echo "  [OK]  Added to ${BASHRC}:"
        echo "          ${SOURCE_LINE}"
    fi
else
    echo "  [!!]  env.sh not found at ${ENV_FILE} — PATH not wired."
    echo "        Run individual bootstraps first, then re-run install.sh."
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo ""
_box_top
_box_line "  airgap-cpp-devkit — Installation Complete"
_box_mid
_box_line "  Platform : ${OS}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
_box_mid

if [[ ${#INSTALLED_TOOLS[@]} -gt 0 ]]; then
    _box_line "  Installed:"
    for t in "${INSTALLED_TOOLS[@]}"; do
        _box_line "    [OK]  ${t}"
    done
fi

if [[ ${#SKIPPED_TOOLS[@]} -gt 0 ]]; then
    _box_line "  Skipped:"
    for t in "${SKIPPED_TOOLS[@]}"; do
        _box_line "    [--]  ${t}"
    done
fi

if [[ ${#FAILED_TOOLS[@]} -gt 0 ]]; then
    _box_line "  FAILED:"
    for t in "${FAILED_TOOLS[@]}"; do
        _box_line "    [!!]  ${t}"
    done
fi

_box_mid
if [[ -f "${ENV_FILE}" ]]; then
    _box_line "  PATH env : ${ENV_FILE}"
    _box_line "  Activate : source \"${ENV_FILE}\""
fi
_box_bot

echo ""
if [[ ${#FAILED_TOOLS[@]} -gt 0 ]]; then
    echo "  [!!] Some tools failed to install. Check the log files in:"
    case "${OS}" in
        windows) echo "         %TEMP%\\airgap-cpp-devkit\\logs\\" ;;
        linux)   echo "         /var/log/airgap-cpp-devkit/ or ~/airgap-cpp-devkit-logs/" ;;
    esac
    echo ""
    exit 1
fi

echo "  Restart your shell or run:"
echo "    source \"${ENV_FILE}\""
echo ""
echo "  All tools will then be available on PATH."
echo ""