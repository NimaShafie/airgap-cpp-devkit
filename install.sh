#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# install.sh
#
# Top-level orchestrator for airgap-cpp-devkit.
# Installs all tools in the correct order and wires PATH into ~/.bashrc.
#
# REQUIRED tools (installed automatically):
#   - toolchains/clang  (clang-format + clang-tidy)
#   - cmake       4.3.0
#   - python      3.14.3  (portable interpreter)
#   - lcov        2.4  (Linux only)
#   - style-formatter  (pre-commit hook)
#
# OPTIONAL tools (prompted):
#   - 7zip               (Windows + Linux, admin + user)
#   - dev-tools/vscode-extensions  (requires VS Code + 'code' on PATH)
#   - winlibs-gcc-ucrt   (Windows only)
#   - frameworks/grpc  (Windows only, requires Visual Studio)
#
# USAGE:
#   bash install.sh [--prefix <path>] [--rebuild] [--yes]
#
# OPTIONS:
#   --prefix <path>   Override install prefix for all tools
#   --rebuild         Force reinstall of all tools
#   --yes             Non-interactive: use defaults, skip confirmation screen
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
# Source install-mode library (for box helpers + im_progress_*)
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"

# ---------------------------------------------------------------------------
# Box helpers (local — install-mode not fully init'd yet)
# ---------------------------------------------------------------------------
_W=98
_box_top()  { local l=""; local i; for((i=0;i<_W;i++)); do l+="═"; done; printf '╔%s╗\n' "${l}"; }
_box_mid()  { local l=""; local i; for((i=0;i<_W;i++)); do l+="═"; done; printf '╠%s╣\n' "${l}"; }
_box_bot()  { local l=""; local i; for((i=0;i<_W;i++)); do l+="═"; done; printf '╚%s╝\n' "${l}"; }
_box_line() {
    local str="$1"
    if (( ${#str} > _W )); then str="${str:0:$(( _W - 3 ))}..."; fi
    local pad=$(( _W - ${#str} ))
    printf '║%s%*s║\n' "${str}" "${pad}" ""
}
_box_blank() { printf '║%*s║\n' "${_W}" ""; }

# ---------------------------------------------------------------------------
# Determine install prefix candidates
# ---------------------------------------------------------------------------
_get_sys_prefix() {
    case "${OS}" in
        windows)
            local pf
            pf="$(cygpath -u "${PROGRAMFILES:-/c/Program Files}" 2>/dev/null || echo "/c/Program Files")"
            echo "${pf}/airgap-cpp-devkit"
            ;;
        linux) echo "/opt/airgap-cpp-devkit" ;;
    esac
}

_get_user_prefix() {
    case "${OS}" in
        windows)
            local lad
            lad="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null || echo "${HOME}/AppData/Local")"
            echo "${lad}/airgap-cpp-devkit"
            ;;
        linux) echo "${HOME}/.local/share/airgap-cpp-devkit" ;;
    esac
}

SYS_PREFIX="$(_get_sys_prefix)"
USER_PREFIX="$(_get_user_prefix)"

# ---------------------------------------------------------------------------
# CONFIRMATION SCREEN
# ---------------------------------------------------------------------------
if [[ "${AUTO_YES}" == "false" ]]; then

    echo ""
    _box_top
    _box_line "  airgap-cpp-devkit — Installation Wizard"
    _box_mid
    _box_line "  Platform : ${OS}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
    _box_blank
    _box_line "  REQUIRED (installed automatically):"
    _box_line "    [1] toolchains/clang         clang-format + clang-tidy 22.1.2"
    _box_line "    [2] cmake              4.3.0"
    _box_line "    [3] python             3.14.3 (portable interpreter)"
    if [[ "${OS}" == "linux" ]]; then
    _box_line "    [4] lcov               2.4 (Linux only)"
    fi
    _box_line "    [5] style-formatter    pre-commit hook"
    _box_blank
    _box_line "  OPTIONAL (you will be prompted):"
    _box_line "    [6] 7zip               26.00 (Windows + Linux, admin + user)"
    _box_line "    [7] servy              7.3 (Windows service manager, Windows only)"
    _box_line "    [8] dev-tools/vscode-extensions  C/C++, TestMate, Python (requires 'code' on PATH)"
    if [[ "${OS}" == "windows" ]]; then
    _box_line "    [8] winlibs-gcc-ucrt   GCC 15.2.0 + MinGW-w64"
    _box_line "    [9] frameworks/grpc  gRPC C++ (requires Visual Studio)"
    fi
    _box_blank
    _box_mid
    _box_line "  INSTALL MODE"
    _box_blank
    _box_line "  [A] System-wide (admin)   -> ${SYS_PREFIX}"
    _box_line "  [U] Current user only     -> ${USER_PREFIX}"
    _box_line "  [C] Custom prefix         -> specify your own path"
    _box_blank
    _box_bot
    echo ""

    # --- Install mode choice ---
    while true; do
        printf "  Choose install mode [A/U/C]: "
        read -r MODE_CHOICE
        case "${MODE_CHOICE^^}" in
            A)
                export INSTALL_PREFIX_OVERRIDE="${SYS_PREFIX}"
                echo "  [OK] System-wide install: ${SYS_PREFIX}"
                break ;;
            U)
                export INSTALL_PREFIX_OVERRIDE="${USER_PREFIX}"
                echo "  [OK] User install: ${USER_PREFIX}"
                break ;;
            C)
                printf "  Enter custom prefix path: "
                read -r CUSTOM_PATH
                if [[ -z "${CUSTOM_PATH}" ]]; then
                    echo "  [!!] Path cannot be empty."
                else
                    export INSTALL_PREFIX_OVERRIDE="${CUSTOM_PATH}"
                    echo "  [OK] Custom install: ${CUSTOM_PATH}"
                    break
                fi ;;
            *) echo "  [!!] Invalid choice. Enter A, U, or C." ;;
        esac
    done

    echo ""

    # --- Optional tools ---
    INSTALL_7ZIP=false
    INSTALL_VSCODE=false
    INSTALL_WINLIBS=false
    INSTALL_GRPC=false
    GRPC_VERSION="1.76.0"

    printf "  Install 7zip 26.00? (archive tool, Windows + Linux) [y/N]: "
    read -r reply
    [[ "${reply^^}" == "Y" ]] && INSTALL_7ZIP=true

    printf "  Install servy 7.3? (Windows service manager, Windows only) [y/N]: "
    read -r reply
    [[ "${reply^^}" == "Y" ]] && INSTALL_SERVY=true

    printf "  Install dev-tools/vscode-extensions? (requires 'code' on PATH) [y/N]: "
    read -r reply
    [[ "${reply^^}" == "Y" ]] && INSTALL_VSCODE=true

    if [[ "${OS}" == "windows" ]]; then
        printf "  Install winlibs-gcc-ucrt? (GCC 15.2.0 + MinGW-w64) [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_WINLIBS=true

        printf "  Install frameworks/grpc? (requires Visual Studio) [y/N]: "
        read -r reply
        if [[ "${reply^^}" == "Y" ]]; then
            INSTALL_GRPC=true
            echo ""
            echo "  gRPC version:"
            echo "    [1] 1.76.0  (production-tested, default)"
            echo "    [2] 1.78.1  (latest candidate)"
            printf "  Choose [1/2, default=1]: "
            read -r ver_choice
            case "${ver_choice}" in
                2) GRPC_VERSION="1.78.1" ;;
                *) GRPC_VERSION="1.76.0" ;;
            esac
            echo "  [OK] gRPC version: ${GRPC_VERSION}"
        fi
        echo ""
    fi

    # --- Final confirmation ---
    echo ""
    _box_top
    _box_line "  Ready to install — please confirm"
    _box_mid
    _box_line "  Install prefix : ${INSTALL_PREFIX_OVERRIDE}"
    _box_line "  Rebuild        : ${REBUILD}"
    _box_blank
    _box_line "  Tools to install:"
    _box_line "    [OK] toolchains/clang, cmake, python, style-formatter"
    [[ "${OS}" == "linux" ]] && _box_line "    [OK] lcov"
    [[ "${INSTALL_7ZIP}" == "true" ]]     && _box_line "    [OK] 7zip 26.00"
    [[ "${INSTALL_SERVY}" == "true" ]]    && _box_line "    [OK] servy 7.3 (Windows only)"
    [[ "${INSTALL_VSCODE}" == "true" ]]   && _box_line "    [OK] dev-tools/vscode-extensions"
    [[ "${INSTALL_WINLIBS}" == "true" ]]  && _box_line "    [OK] winlibs-gcc-ucrt"
    [[ "${INSTALL_GRPC}" == "true" ]]     && _box_line "    [OK] frameworks/grpc ${GRPC_VERSION}"
    _box_bot
    echo ""
    printf "  Press Enter to begin installation, or Ctrl+C to cancel..."
    read -r

else
    # --yes mode: use defaults
    if [[ -n "${PREFIX_OVERRIDE}" ]]; then
        export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
    else
        export INSTALL_PREFIX_OVERRIDE="${USER_PREFIX}"
    fi
    INSTALL_7ZIP=false
    INSTALL_SERVY=false
    INSTALL_VSCODE=false
    INSTALL_WINLIBS=false
    INSTALL_GRPC=false
    GRPC_VERSION="1.76.0"
    echo ""
    echo "  [--yes] Non-interactive mode. Installing to: ${INSTALL_PREFIX_OVERRIDE}"
    echo ""
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
INSTALLED_TOOLS=()
FAILED_TOOLS=()
SKIPPED_TOOLS=()

_run_bootstrap_winlibs() {
    local label="$1" script="$2"
    local tool_prefix="${INSTALL_PREFIX_OVERRIDE}/${label}"
    echo ""
    echo "  -- ${label} ------------------------------------------------------"
    local rebuild_arg=()
    [[ "${REBUILD}" == "true" ]] && rebuild_arg=("--rebuild")
    if bash "${script}" "x86_64" --prefix "${tool_prefix}" "${rebuild_arg[@]}"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} FAILED — continuing with remaining tools."
    fi
}

_run_bootstrap_no_prefix() {
    local label="$1" script="$2"
    shift 2
    echo ""
    echo "  -- ${label} ------------------------------------------------------"
    local rebuild_arg=()
    [[ "${REBUILD}" == "true" ]] && rebuild_arg=("--rebuild")
    if bash "${script}" "${rebuild_arg[@]}"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} FAILED — continuing with remaining tools."
    fi
}

_run_bootstrap() {
    local label="$1" script="$2"
    shift 2
    local extra_args=("$@")

    echo ""
    echo "  ── ${label} ──────────────────────────────────────────────────────"

    local rebuild_arg=()
    [[ "${REBUILD}" == "true" ]] && rebuild_arg=("--rebuild")

    local tool_prefix="${INSTALL_PREFIX_OVERRIDE}/${label}"
    if bash "${script}" \
        --prefix "${tool_prefix}" \
        "${rebuild_arg[@]}" \
        "${extra_args[@]}"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} FAILED — continuing with remaining tools."
    fi
}

_run_setup() {
    local label="$1" script="$2"
    shift 2
    echo ""
    echo "  ── ${label} ──────────────────────────────────────────────────────"
    if bash "${script}" "$@"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} FAILED — continuing with remaining tools."
    fi
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
_box_top
_box_line "  airgap-cpp-devkit — Installing"
_box_mid
_box_line "  Platform : ${OS}   Prefix : ${INSTALL_PREFIX_OVERRIDE}"
_box_bot
echo ""

# ---------------------------------------------------------------------------
# Step 1: prebuilt-binaries submodule
# ---------------------------------------------------------------------------
echo "  [1/9] Checking prebuilt-binaries submodule..."
if ! git -C "${REPO_ROOT}" submodule status prebuilt-binaries 2>/dev/null | grep -q "^[^-]"; then
    im_progress_start "Initialising prebuilt-binaries submodule"
    git -C "${REPO_ROOT}" submodule update --init --recursive prebuilt-binaries
    im_progress_stop "Submodule ready"
else
    echo "  [OK]  prebuilt-binaries already initialized."
fi

# ---------------------------------------------------------------------------
# Step 2: toolchains/clang
# ---------------------------------------------------------------------------
echo ""
echo "  [2/9] Installing toolchains/clang (required)..."
_run_bootstrap "toolchains/clang" \
    "${REPO_ROOT}/toolchains/clang/source-build/setup.sh"

# ---------------------------------------------------------------------------
# Step 3: cmake
# ---------------------------------------------------------------------------
echo ""
echo "  [3/9] Installing cmake (required)..."
_run_bootstrap "cmake" \
    "${REPO_ROOT}/cmake/bootstrap.sh"

# ---------------------------------------------------------------------------
# Step 4: python
# ---------------------------------------------------------------------------
echo ""
echo "  [4/9] Installing python (required)..."
_run_bootstrap "python" \
    "${REPO_ROOT}/python/bootstrap.sh"

# ---------------------------------------------------------------------------
# Step 5: lcov (Linux only)
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]]; then
    echo ""
    echo "  [5/9] Installing lcov (required on Linux)..."
    _run_bootstrap "lcov" \
        "${REPO_ROOT}/build-tools/lcov/setup.sh"
else
    echo ""
    echo "  [5/9] lcov — skipped (Linux only)"
    SKIPPED_TOOLS+=("lcov (Linux only)")
fi

# ---------------------------------------------------------------------------
# Step 6: style-formatter
# ---------------------------------------------------------------------------
echo ""
echo "  [6/9] Installing style-formatter (required)..."
_run_bootstrap_no_prefix "style-formatter" \
    "${REPO_ROOT}/toolchains/clang/style-formatter/bootstrap.sh"

# ---------------------------------------------------------------------------
# Step 7: 7zip (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [7/10] 7-Zip 26.00 (optional)..."
if [[ "${INSTALL_7ZIP}" == "true" ]]; then
    _run_setup "7zip" "${REPO_ROOT}/dev-tools/7zip/setup.sh"
else
    echo "  [--]  Skipped: 7zip"
    SKIPPED_TOOLS+=("7zip")
fi

# ---------------------------------------------------------------------------
# Step 8: servy (optional, Windows only — exits cleanly on Linux)
# ---------------------------------------------------------------------------
echo ""
echo "  [8/10] Servy 7.3 (optional, Windows only)..."
if [[ "${INSTALL_SERVY}" == "true" ]]; then
    _run_setup "servy" "${REPO_ROOT}/dev-tools/servy/setup.sh"
else
    echo "  [--]  Skipped: servy"
    SKIPPED_TOOLS+=("servy")
fi

# ---------------------------------------------------------------------------
# Step 9: dev-tools/vscode-extensions (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [9/10] VS Code extensions (optional)..."
if [[ "${INSTALL_VSCODE}" == "true" ]]; then
    _run_bootstrap_no_prefix "dev-tools/vscode-extensions" \
        "${REPO_ROOT}/dev-tools/vscode-extensions/setup.sh"
else
    echo "  [--]  Skipped: dev-tools/vscode-extensions"
    SKIPPED_TOOLS+=("dev-tools/vscode-extensions")
fi

# ---------------------------------------------------------------------------
# Step 10: optional platform tools
# ---------------------------------------------------------------------------
echo ""
echo "  [10/10] Optional platform tools..."

if [[ "${OS}" == "windows" ]]; then
    if [[ "${INSTALL_WINLIBS}" == "true" ]]; then
        _run_bootstrap_winlibs "winlibs-gcc-ucrt" \
            "${REPO_ROOT}/toolchains/gcc/windows/setup.sh"
    else
        echo "  [--]  Skipped: winlibs-gcc-ucrt"
        SKIPPED_TOOLS+=("winlibs-gcc-ucrt")
    fi

    if [[ "${INSTALL_GRPC}" == "true" ]]; then
        _run_bootstrap "grpc-${GRPC_VERSION}" \
            "${REPO_ROOT}/frameworks/grpc/setup_grpc.sh" \
            "--version" "${GRPC_VERSION}"
    else
        echo "  [--]  Skipped: frameworks/grpc"
        SKIPPED_TOOLS+=("frameworks/grpc")
    fi
else
    echo "  [--]  winlibs-gcc-ucrt  — skipped (Windows only)"
    echo "  [--]  frameworks/grpc — skipped (Windows only)"
    SKIPPED_TOOLS+=("winlibs-gcc-ucrt (Windows only)" "frameworks/grpc (Windows only)")
fi

# ---------------------------------------------------------------------------
# Wire env.sh into ~/.bashrc
# ---------------------------------------------------------------------------
echo ""
echo "  Wiring env.sh into ~/.bashrc..."

ENV_DIR="${INSTALL_PREFIX_OVERRIDE}"
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
        echo "  [OK]  Added to ${BASHRC}: ${SOURCE_LINE}"
    fi
else
    echo "  [!!]  env.sh not found at ${ENV_FILE}"
    echo "        PATH not wired — source manually after install completes."
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
_box_line "  Prefix  : ${INSTALL_PREFIX_OVERRIDE}"
[[ -f "${ENV_FILE}" ]] && _box_line "  env.sh  : ${ENV_FILE}"
_box_bot

echo ""
if [[ ${#FAILED_TOOLS[@]} -gt 0 ]]; then
    echo "  [!!] Some tools failed. Check logs in:"
    case "${OS}" in
        windows) echo "         %TEMP%\\airgap-cpp-devkit\\logs\\" ;;
        linux)   echo "         /var/log/airgap-cpp-devkit/" ;;
    esac
    echo ""
    exit 1
fi

echo "  Restart your shell or run:"
[[ -f "${ENV_FILE}" ]] && echo "    source \"${ENV_FILE}\""
echo ""
echo "  All installed tools will then be available on PATH."
echo ""