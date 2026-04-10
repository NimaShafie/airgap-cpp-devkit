#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# install.sh
#
# Top-level orchestrator for airgap-cpp-devkit.
# Installs all tools in the correct order and wires PATH into ~/.bashrc.
#
# REQUIRED tools (installed automatically):
#   - toolchains/clang  (clang-format + clang-tidy 22.1.2)
#   - cmake       4.3.1
#   - python      3.14.4  (portable interpreter)
#   - lcov        2.4  (Linux only)
#   - style-formatter  (pre-commit hook)
#
# OPTIONAL tools (prompted):
#   - 7zip               26.00  (Windows + Linux, admin + user)
#   - servy              7.8    (Windows only)
#   - conan              2.27.0 (Windows + Linux, no Python required)
#   - dev-tools/vscode-extensions  (requires VS Code + 'code' on PATH)
#   - winlibs-gcc-ucrt   (Windows only)
#   - frameworks/grpc    (Windows only, requires Visual Studio)
#   - sqlite             3.53.0 (CLI binary, Windows + Linux)
#   - matlab             (verification only -- checks Database Toolbox + Compiler)
#
# USAGE:
#   bash install.sh [--prefix <path>] [--rebuild] [--yes]
#
# OPTIONS:
#   --prefix <path>   Override install prefix for all tools
#   --rebuild         Force reinstall of all tools
#   --yes             Non-interactive: use defaults, skip confirmation screen
#   --profile <name>  Pre-select tools for a team profile (skips prompts):
#                       cpp-dev   -- clang, cmake, python, conan, vscode, sqlite
#                       devops    -- cmake, python, conan, sqlite, 7zip
#                       minimal   -- clang, cmake, python only (no optionals)
#                       full      -- all optional tools enabled
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
PROFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  PREFIX_OVERRIDE="$2"; shift 2 ;;
        --rebuild) REBUILD=true; shift ;;
        --yes)     AUTO_YES=true; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
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
# Source install-mode library
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"

# ---------------------------------------------------------------------------
# Plain ASCII display helpers
# ---------------------------------------------------------------------------
_sep()    { printf '%s\n' "--------------------------------------------------------------------------------"; }
_sep2()   { printf '%s\n' "================================================================================"; }
_header() { _sep2; printf '  %s\n' "$1"; _sep2; }
_section(){ _sep;  printf '  %s\n' "$1"; _sep; }

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
    _header "  airgap-cpp-devkit -- Installation Wizard"
    echo ""
    echo "  Platform : ${OS}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    _section "  REQUIRED (installed automatically)"
    echo "    [1] toolchains/clang         clang-format + clang-tidy 22.1.2"
    echo "    [2] cmake                    4.3.1"
    echo "    [3] python                   3.14.4 (portable interpreter)"
    if [[ "${OS}" == "linux" ]]; then
    echo "    [4] lcov                     2.4 (Linux only)"
    fi
    echo "    [5] style-formatter          pre-commit hook"
    echo ""
    _section "  OPTIONAL (you will be prompted)"
    echo "  Cross-platform:"
    echo "    [6] conan          2.27.0   C/C++ package manager            [~5s]"
    echo "    [7] sqlite         3.53.0   Database inspection CLI          [~3s]"
    echo "    [8] 7zip           26.00    Archive tool                     [~2s]"
    echo "    [9] vscode-ext              C/C++, TestMate, Python          [~30s]"
    echo "   [10] matlab                  Toolbox verification             [~2s]"
    if [[ "${OS}" == "windows" ]]; then
    echo ""
    echo "  Windows-only:"
    echo "   [11] servy          7.8      Windows service manager          [~3s]"
    echo "   [12] winlibs-gcc   15.2.0   GCC + MinGW-w64                [~8min]"
    echo "   [13] grpc           1.78.1   C++ framework (needs VS)       [~20min]"
    fi
    echo ""
    echo "  Tip: use --profile <name> to skip prompts"
    echo "       Profiles: cpp-dev | devops | minimal | full"
    echo ""
    _section "  INSTALL MODE"
    echo ""
    echo "  [A] System-wide (admin)   ->  ${SYS_PREFIX}"
    echo "  [U] Current user only     ->  ${USER_PREFIX}"
    echo "  [C] Custom prefix         ->  specify your own path"
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
    INSTALL_SERVY=false
    INSTALL_CONAN=false
    INSTALL_VSCODE=false
    INSTALL_WINLIBS=false
    INSTALL_GRPC=false
    INSTALL_SQLITE=false
    INSTALL_MATLAB=false
    GRPC_VERSION="1.78.1"

    # Apply profile pre-selections if specified
    _apply_profile() {
        case "${PROFILE}" in
            cpp-dev)
                INSTALL_CONAN=true; INSTALL_VSCODE=true
                INSTALL_SQLITE=true; INSTALL_7ZIP=true
                echo "  [OK] Profile: cpp-dev (conan, vscode, sqlite, 7zip)"
                ;;
            devops)
                INSTALL_CONAN=true; INSTALL_SQLITE=true
                INSTALL_7ZIP=true
                echo "  [OK] Profile: devops (conan, sqlite, 7zip)"
                ;;
            minimal)
                echo "  [OK] Profile: minimal (required tools only)"
                ;;
            full)
                INSTALL_7ZIP=true; INSTALL_CONAN=true
                INSTALL_VSCODE=true; INSTALL_SQLITE=true
                INSTALL_MATLAB=true
                if [[ "${OS}" == "windows" ]]; then
                    INSTALL_SERVY=true; INSTALL_WINLIBS=true; INSTALL_GRPC=true
                fi
                echo "  [OK] Profile: full (all optional tools)"
                ;;
            "")
                # No profile -- use interactive prompts below
                ;;
            *)
                echo "  [!!] Unknown profile: ${PROFILE}. Valid: cpp-dev, devops, minimal, full" >&2
                exit 1
                ;;
        esac
    }
    _apply_profile

    if [[ -z "${PROFILE}" ]]; then
        # --- Cross-platform tools ---
        printf "  Install conan 2.27.0?          C/C++ package manager       [~5s]  [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_CONAN=true

        printf "  Install sqlite 3.53.0 CLI?     Database inspection tool    [~3s]  [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_SQLITE=true

        printf "  Install 7zip 26.00?            Archive tool                [~2s]  [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_7ZIP=true

        printf "  Install vscode-extensions?     C/C++, Python (needs 'code')[~30s] [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_VSCODE=true

        printf "  Install matlab verification?   Checks toolboxes            [~2s]  [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_MATLAB=true

        # --- Windows-only tools ---
        if [[ "${OS}" == "windows" ]]; then
            echo ""
            echo "  --- Windows-only tools ---"
            printf "  Install servy 7.8?             Windows service manager     [~3s]  [y/N]: "
            read -r reply
            [[ "${reply^^}" == "Y" ]] && INSTALL_SERVY=true

            printf "  Install winlibs-gcc-ucrt?      GCC 15.2.0 + MinGW-w64     [~8min]  [y/N]: "
            read -r reply
            [[ "${reply^^}" == "Y" ]] && INSTALL_WINLIBS=true

            printf "  Install frameworks/grpc?       Requires Visual Studio      [~20min] [y/N]: "
            read -r reply
            if [[ "${reply^^}" == "Y" ]]; then
                INSTALL_GRPC=true
                echo ""
                echo "  gRPC version:"
                echo "    [1] 1.78.1  (default)"
                printf "  Choose [1, default=1]: "
                read -r ver_choice
                case "${ver_choice}" in
                    *) GRPC_VERSION="1.78.1" ;;
                esac
                echo "  [OK] gRPC version: ${GRPC_VERSION}"
            fi
        fi
    fi

    # --- Final confirmation ---
    echo ""
    _header "  Ready to install -- please confirm"
    echo ""
    echo "  Install prefix : ${INSTALL_PREFIX_OVERRIDE}"
    echo "  Rebuild        : ${REBUILD}"
    echo ""
    echo "  Tools to install:"
    echo "    [OK] toolchains/clang, cmake 4.3.1, python 3.14.4, style-formatter"
    [[ "${OS}" == "linux" ]]              && echo "    [OK] lcov 2.4"
    [[ "${INSTALL_7ZIP}"    == "true" ]]  && echo "    [OK] 7zip 26.00"
    [[ "${INSTALL_SERVY}"   == "true" ]]  && echo "    [OK] servy 7.8 (Windows only)"
    [[ "${INSTALL_CONAN}"   == "true" ]]  && echo "    [OK] conan 2.27.0"
    [[ "${INSTALL_VSCODE}"  == "true" ]]  && echo "    [OK] dev-tools/vscode-extensions"
    [[ "${INSTALL_WINLIBS}" == "true" ]]  && echo "    [OK] winlibs-gcc-ucrt"
    [[ "${INSTALL_GRPC}"    == "true" ]]  && echo "    [OK] frameworks/grpc ${GRPC_VERSION}"
    [[ "${INSTALL_SQLITE}"  == "true" ]]  && echo "    [OK] sqlite 3.53.0"
    [[ "${INSTALL_MATLAB}"  == "true" ]]  && echo "    [OK] matlab (verification only)"
    echo ""
    _sep2
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
    INSTALL_CONAN=false
    INSTALL_VSCODE=false
    INSTALL_WINLIBS=false
    INSTALL_GRPC=false
    INSTALL_SQLITE=false
    INSTALL_MATLAB=false
    GRPC_VERSION="1.78.1"

    # Apply profile if given with --yes
    if [[ -n "${PROFILE}" ]]; then
        case "${PROFILE}" in
            cpp-dev)  INSTALL_CONAN=true; INSTALL_VSCODE=true; INSTALL_SQLITE=true; INSTALL_7ZIP=true ;;
            devops)   INSTALL_CONAN=true; INSTALL_SQLITE=true; INSTALL_7ZIP=true ;;
            minimal)  ;;
            full)
                INSTALL_7ZIP=true; INSTALL_CONAN=true; INSTALL_VSCODE=true
                INSTALL_SQLITE=true; INSTALL_MATLAB=true
                [[ "${OS}" == "windows" ]] && { INSTALL_SERVY=true; INSTALL_WINLIBS=true; INSTALL_GRPC=true; }
                ;;
        esac
    fi

    echo ""
    echo "  [--yes] Non-interactive mode. Installing to: ${INSTALL_PREFIX_OVERRIDE}"
    [[ -n "${PROFILE}" ]] && echo "  [--yes] Profile: ${PROFILE}"
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
    _sep
    echo "  ${label}"
    _sep
    local rebuild_arg=()
    [[ "${REBUILD}" == "true" ]] && rebuild_arg=("--rebuild")
    if bash "${script}" "x86_64" --prefix "${tool_prefix}" "${rebuild_arg[@]}"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} FAILED -- continuing with remaining tools."
    fi
}

_run_bootstrap_no_prefix() {
    local label="$1" script="$2"
    shift 2
    echo ""
    _sep
    echo "  ${label}"
    _sep
    local rebuild_arg=()
    [[ "${REBUILD}" == "true" ]] && rebuild_arg=("--rebuild")
    if bash "${script}" "${rebuild_arg[@]}"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} FAILED -- continuing with remaining tools."
    fi
}

_run_bootstrap() {
    local label="$1" script="$2"
    shift 2
    local extra_args=("$@")
    echo ""
    _sep
    echo "  ${label}"
    _sep
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
        echo "  [!!] ${label} FAILED -- continuing with remaining tools."
    fi
}

_run_setup() {
    local label="$1" script="$2"
    shift 2
    echo ""
    _sep
    echo "  ${label}"
    _sep
    if bash "${script}" "$@"; then
        INSTALLED_TOOLS+=("${label}")
    else
        FAILED_TOOLS+=("${label}")
        echo ""
        echo "  [!!] ${label} FAILED -- continuing with remaining tools."
    fi
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
_header "  airgap-cpp-devkit -- Installing"
echo ""
echo "  Platform : ${OS}   Prefix : ${INSTALL_PREFIX_OVERRIDE}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: prebuilt-binaries submodule
# ---------------------------------------------------------------------------
echo "  [1/13] Checking prebuilt-binaries submodule..."
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
echo "  [2/13] Installing toolchains/clang (required)..."
_run_bootstrap "toolchains/clang" \
    "${REPO_ROOT}/toolchains/clang/source-build/setup.sh"

# ---------------------------------------------------------------------------
# Step 3: cmake
# ---------------------------------------------------------------------------
echo ""
echo "  [3/13] Installing cmake 4.3.1 (required)..."
_run_bootstrap "cmake" \
    "${REPO_ROOT}/build-tools/cmake/setup.sh"

# ---------------------------------------------------------------------------
# Step 4: python
# ---------------------------------------------------------------------------
echo ""
echo "  [4/13] Installing python 3.14.4 (required)..."
_run_bootstrap "python" \
    "${REPO_ROOT}/languages/python/setup.sh"

# ---------------------------------------------------------------------------
# Step 5: lcov (Linux only)
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]]; then
    echo ""
    echo "  [5/13] Installing lcov 2.4 (required on Linux)..."
    _run_bootstrap "lcov" \
        "${REPO_ROOT}/build-tools/lcov/setup.sh"
else
    echo ""
    echo "  [5/13] lcov -- skipped (Linux only)"
    SKIPPED_TOOLS+=("lcov (Linux only)")
fi

# ---------------------------------------------------------------------------
# Step 6: style-formatter
# ---------------------------------------------------------------------------
echo ""
echo "  [6/13] Installing style-formatter (required)..."
_run_bootstrap_no_prefix "style-formatter" \
    "${REPO_ROOT}/toolchains/clang/style-formatter/bootstrap.sh"

# ---------------------------------------------------------------------------
# Step 7: 7zip (optional)
# ---------------------------------------------------------------------------
echo ""
echo "  [7/13] 7-Zip 26.00 (optional)..."
if [[ "${INSTALL_7ZIP}" == "true" ]]; then
    _run_setup "7zip" "${REPO_ROOT}/dev-tools/7zip/setup.sh"
else
    echo "  [--]  Skipped: 7zip"
    SKIPPED_TOOLS+=("7zip")
fi

# ---------------------------------------------------------------------------
# Step 8: servy (optional, Windows only)
# ---------------------------------------------------------------------------
echo ""
echo "  [8/13] Servy 7.8 (optional, Windows only)..."
if [[ "${INSTALL_SERVY}" == "true" ]]; then
    _run_setup "servy" "${REPO_ROOT}/dev-tools/servy/setup.sh"
else
    echo "  [--]  Skipped: servy"
    SKIPPED_TOOLS+=("servy")
fi

# ---------------------------------------------------------------------------
# Step 9: conan (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [9/13] Conan 2.27.0 (optional)..."
if [[ "${INSTALL_CONAN}" == "true" ]]; then
    _run_setup "conan" "${REPO_ROOT}/dev-tools/conan/setup.sh"
else
    echo "  [--]  Skipped: conan"
    SKIPPED_TOOLS+=("conan")
fi

# ---------------------------------------------------------------------------
# Step 10: dev-tools/vscode-extensions (optional)
# ---------------------------------------------------------------------------
echo ""
echo "  [10/13] VS Code extensions (optional)..."
if [[ "${INSTALL_VSCODE}" == "true" ]]; then
    _run_bootstrap_no_prefix "dev-tools/vscode-extensions" \
        "${REPO_ROOT}/dev-tools/vscode-extensions/setup.sh"
else
    echo "  [--]  Skipped: dev-tools/vscode-extensions"
    SKIPPED_TOOLS+=("dev-tools/vscode-extensions")
fi

# ---------------------------------------------------------------------------
# Step 11: optional platform tools (Windows only)
# ---------------------------------------------------------------------------
echo ""
echo "  [11/13] Optional platform tools..."
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
    echo "  [--]  winlibs-gcc-ucrt  -- skipped (Windows only)"
    echo "  [--]  frameworks/grpc  -- skipped (Windows only)"
    SKIPPED_TOOLS+=("winlibs-gcc-ucrt (Windows only)" "frameworks/grpc (Windows only)")
fi

# ---------------------------------------------------------------------------
# Step 12: SQLite CLI (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [12/13] SQLite 3.53.0 CLI (optional)..."
if [[ "${INSTALL_SQLITE}" == "true" ]]; then
    _run_setup "sqlite" "${REPO_ROOT}/dev-tools/sqlite/setup.sh"
else
    echo "  [--]  Skipped: sqlite"
    SKIPPED_TOOLS+=("sqlite")
fi

# ---------------------------------------------------------------------------
# Step 13: MATLAB verification (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [13/13] MATLAB toolbox verification (optional)..."
if [[ "${INSTALL_MATLAB}" == "true" ]]; then
    _run_bootstrap_no_prefix "matlab" \
        "${REPO_ROOT}/dev-tools/matlab/setup.sh"
else
    echo "  [--]  Skipped: matlab"
    SKIPPED_TOOLS+=("matlab")
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
        echo "# airgap-cpp-devkit -- added by install.sh" >> "${BASHRC}"
        echo "${SOURCE_LINE}" >> "${BASHRC}"
        echo "  [OK]  Added to ${BASHRC}: ${SOURCE_LINE}"
    fi
else
    echo "  [!!]  env.sh not found at ${ENV_FILE}"
    echo "        PATH not wired -- source manually after install completes."
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo ""
_header "  airgap-cpp-devkit -- Installation Complete"
echo ""
echo "  Platform : ${OS}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

if [[ ${#INSTALLED_TOOLS[@]} -gt 0 ]]; then
    echo "  Installed:"
    for t in "${INSTALLED_TOOLS[@]}"; do
        echo "    [OK]  ${t}"
    done
    echo ""
fi

if [[ ${#SKIPPED_TOOLS[@]} -gt 0 ]]; then
    echo "  Skipped:"
    for t in "${SKIPPED_TOOLS[@]}"; do
        echo "    [--]  ${t}"
    done
    echo ""
fi

if [[ ${#FAILED_TOOLS[@]} -gt 0 ]]; then
    echo "  FAILED:"
    for t in "${FAILED_TOOLS[@]}"; do
        echo "    [!!]  ${t}"
    done
    echo ""
fi

_sep2
echo ""
echo "  Prefix  : ${INSTALL_PREFIX_OVERRIDE}"
[[ -f "${ENV_FILE}" ]] && echo "  env.sh  : ${ENV_FILE}"
echo ""

if [[ ${#FAILED_TOOLS[@]} -gt 0 ]]; then
    echo "  [!!] Some tools failed. Check logs in:"
    case "${OS}" in
        windows) echo "         %TEMP%\\airgap-cpp-devkit\\logs\\" ;;
        linux)   echo "         /var/log/airgap-cpp-devkit/" >&2 ;;
    esac
    echo ""
    exit 1
fi

echo "  Restart your shell or run:"
[[ -f "${ENV_FILE}" ]] && echo "    source \"${ENV_FILE}\""
echo ""
echo "  All installed tools will then be available on PATH."
echo ""