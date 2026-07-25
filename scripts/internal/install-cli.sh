#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# install-cli.sh
#
# CLI installer for airgap-cpp-devkit.
# No Python required — pure Bash, works on Windows (Git Bash / MINGW64) and
# Linux (RHEL/Rocky 8, 9, 10).
#
# PREFERRED entry point (visual UI):
#   bash scripts/launch.sh
#   Opens the DevKit Manager web UI at http://127.0.0.1:9090
#   with one-click installs, profiles, and live log output.
#
# USE THIS SCRIPT WHEN:
#   - You need a non-interactive / scripted install (--yes --profile)
#   - You are in a headless / CI environment with no browser
#
# REQUIRED tools (installed automatically):
#   - tools/toolchains/llvm   (clang-format + clang-tidy 22.1.4)
#   - cmake                   4.3.2
#   - python                  3.14.4  (portable interpreter)
#   - lcov                    2.5  (Linux only)
#   - style-formatter         pre-commit hook
#
# OPTIONAL tools (prompted, or selected via --profile):
#   - servy              7.9    (Windows only)
#   - conan              2.30.0 (Windows + Linux)
#   - tools/dev-tools/vscode-extensions  (requires VS Code + 'code' on PATH)
#   - winlibs-gcc-ucrt   (Windows only)
#   - tools/frameworks/grpc    1.83.0 (Windows: per-VS toolset; Linux: RHEL/Rocky 8/9/10)
#   - sqlite             3.53.0 (CLI binary, Windows + Linux)
#   - zlib               1.3.2  (gzip/DEFLATE library, source build; Windows + Linux)
#   - matlab             (verification only — checks Database Toolbox + Compiler)
#
# USAGE:
#   bash scripts/internal/install-cli.sh [--prefix <path>] [--rebuild] [--yes] [--profile <name>]
#
# OPTIONS:
#   --prefix <path>   Override install prefix for all tools
#   --rebuild         Force reinstall of all tools
#   --yes             Non-interactive: use defaults, skip confirmation screen
#   --profile <name>  Pre-select tools for a team profile (skips prompts):
#                       cpp-dev   -- llvm, cmake, python, conan, vscode, sqlite, zlib
#                       devops    -- cmake, python, conan, sqlite
#                       minimal   -- llvm, cmake, python only (no optionals)
#                       full      -- all optional tools enabled
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PREFIX_OVERRIDE=""
REBUILD=false
AUTO_YES=false
PROFILE=""
ADMIN_INSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  PREFIX_OVERRIDE="$2"; shift 2 ;;
        --rebuild) REBUILD=true; shift ;;
        --yes)     AUTO_YES=true; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --admin)   ADMIN_INSTALL=true; shift ;;
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
source "${REPO_ROOT}/scripts/internal/install-mode.sh"

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
    _header "  airgap-cpp-devkit -- CLI Installer (fallback)"
    echo ""
    echo "  Tip: for a visual installer with live output, run instead:"
    echo "       bash scripts/launch.sh   ->  http://127.0.0.1:9090"
    echo ""
    echo "  Platform : ${OS}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    _section "  REQUIRED (installed automatically)"
    echo "    [1] tools/toolchains/llvm          clang-format + clang-tidy 22.1.4"
    echo "    [2] cmake                    4.3.2"
    echo "    [3] python                   3.14.4 (portable interpreter)"
    if [[ "${OS}" == "linux" ]]; then
    echo "    [4] lcov                     2.5 (Linux only)"
    fi
    echo "    [5] style-formatter          pre-commit hook"
    echo ""
    _section "  OPTIONAL (you will be prompted)"
    echo "  Cross-platform:"
    echo "    [6] conan          2.30.0   C/C++ package manager            [~5s]"
    echo "    [7] sqlite         3.53.0   Database inspection CLI          [~3s]"
    echo "    [8] zlib           1.3.2    gzip/DEFLATE library (source)    [~30s]"
    echo "    [9] vscode-ext              C/C++, TestMate, Python          [~30s]"
    echo "   [10] matlab                  Toolbox verification             [~2s]"
    if [[ "${OS}" == "windows" ]]; then
    echo ""
    echo "  Windows-only:"
    echo "   [11] servy          7.9      Windows service manager          [~3s]"
    echo "   [12] winlibs-gcc   15.2.0   GCC + MinGW-w64                [~8min]"
    echo "   [13] grpc           1.83.0   C++ framework (prebuilt, per-VS)  [~1min]"
    fi
    echo ""
    echo "  Tip: use --profile <name> to skip prompts"
    echo "       Profiles: cpp-dev | devops | minimal | full"
    echo ""
    echo "  Tip: prefer a browser UI? Run instead: bash scripts/launch.sh"
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
    INSTALL_SERVY=false
    INSTALL_CONAN=false
    INSTALL_VSCODE=false
    INSTALL_WINLIBS=false
    INSTALL_GRPC=false
    INSTALL_SQLITE=false
    INSTALL_MATLAB=false
    INSTALL_ZLIB=false
    GRPC_VERSION="1.83.0"
    GRPC_TOOLSET="v143"   # default: Visual Studio 2022

    # Apply profile pre-selections if specified.
    # Profile membership is defined in profiles.defaults.json (repo root); this
    # CLI expresses the same profiles as optional-tool toggles on top of the
    # always-installed core (clang, cmake, python, style-formatter). Keep the
    # selections below consistent with that source.
    _apply_profile() {
        case "${PROFILE}" in
            cpp-dev)
                INSTALL_CONAN=true; INSTALL_VSCODE=true
                INSTALL_SQLITE=true; INSTALL_ZLIB=true
                echo "  [OK] Profile: cpp-dev (conan, vscode, sqlite, zlib)"
                ;;
            devops)
                INSTALL_CONAN=true; INSTALL_SQLITE=true
                echo "  [OK] Profile: devops (conan, sqlite)"
                ;;
            minimal)
                echo "  [OK] Profile: minimal (required tools only)"
                ;;
            full)
                INSTALL_CONAN=true
                INSTALL_VSCODE=true; INSTALL_SQLITE=true
                INSTALL_MATLAB=true; INSTALL_ZLIB=true
                INSTALL_GRPC=true   # Windows: default v143 Release; Linux: RHEL/Rocky 8/9/10 package
                if [[ "${OS}" == "windows" ]]; then
                    INSTALL_SERVY=true; INSTALL_WINLIBS=true
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
        printf "  Install conan 2.30.0?          C/C++ package manager       [~5s]  [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_CONAN=true

        printf "  Install sqlite 3.53.0 CLI?     Database inspection tool    [~3s]  [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_SQLITE=true

        printf "  Install zlib 1.3.2?            gzip/DEFLATE library (build) [~30s] [y/N]: "
        read -r reply
        [[ "${reply^^}" == "Y" ]] && INSTALL_ZLIB=true

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
            printf "  Install servy 7.9?             Windows service manager     [~3s]  [y/N]: "
            read -r reply
            [[ "${reply^^}" == "Y" ]] && INSTALL_SERVY=true

            printf "  Install winlibs-gcc-ucrt?      GCC 15.2.0 + MinGW-w64     [~8min]  [y/N]: "
            read -r reply
            [[ "${reply^^}" == "Y" ]] && INSTALL_WINLIBS=true

            printf "  Install tools/frameworks/grpc 1.83.0? Prebuilt, needs VS toolchain  [~1min] [y/N]: "
            read -r reply
            if [[ "${reply^^}" == "Y" ]]; then
                INSTALL_GRPC=true
                echo ""
                echo "  gRPC ships one prebuilt package per MSVC toolset (Release; Debug"
                echo "  packages also ship — install via devkit-ui). Pick the one matching"
                echo "  your installed Visual Studio (ABI-locked static libs):"
                echo "    [1] Visual Studio 2022  (MSVC v143)   (default)"
                echo "    [2] Visual Studio 2026  (MSVC v145)"
                echo "    [3] Visual Studio 2019  (MSVC v142)"
                printf "  Choose [1-3, default=1]: "
                read -r ts_choice
                case "${ts_choice}" in
                    2) GRPC_TOOLSET="v145" ;;
                    3) GRPC_TOOLSET="v142" ;;
                    *) GRPC_TOOLSET="v143" ;;
                esac
                echo "  [OK] gRPC toolset: ${GRPC_TOOLSET}"
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
    echo "    [OK] tools/toolchains/llvm, cmake 4.3.2, python 3.14.4, style-formatter"
    [[ "${OS}" == "linux" ]]              && echo "    [OK] lcov 2.5"
    [[ "${INSTALL_SERVY}"   == "true" ]]  && echo "    [OK] servy 7.9 (Windows only)"
    [[ "${INSTALL_CONAN}"   == "true" ]]  && echo "    [OK] conan 2.30.0"
    [[ "${INSTALL_VSCODE}"  == "true" ]]  && echo "    [OK] tools/dev-tools/vscode-extensions"
    [[ "${INSTALL_WINLIBS}" == "true" ]]  && echo "    [OK] winlibs-gcc-ucrt"
    if [[ "${INSTALL_GRPC}" == "true" ]]; then
        if [[ "${OS}" == "windows" ]]; then
            echo "    [OK] tools/frameworks/grpc ${GRPC_VERSION} (${GRPC_TOOLSET} Release)"
        else
            echo "    [OK] tools/frameworks/grpc ${GRPC_VERSION} (Linux x86_64)"
        fi
    fi
    [[ "${INSTALL_SQLITE}"  == "true" ]]  && echo "    [OK] sqlite 3.53.0"
    [[ "${INSTALL_ZLIB}"    == "true" ]]  && echo "    [OK] zlib 1.3.2"
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
    elif [[ "${ADMIN_INSTALL}" == "true" ]]; then
        export INSTALL_PREFIX_OVERRIDE="${SYS_PREFIX}"
    else
        export INSTALL_PREFIX_OVERRIDE="${USER_PREFIX}"
    fi
    INSTALL_SERVY=false
    INSTALL_CONAN=false
    INSTALL_VSCODE=false
    INSTALL_WINLIBS=false
    INSTALL_GRPC=false
    INSTALL_SQLITE=false
    INSTALL_MATLAB=false
    INSTALL_ZLIB=false
    GRPC_VERSION="1.83.0"
    GRPC_TOOLSET="v143"

    # Apply profile if given with --yes
    if [[ -n "${PROFILE}" ]]; then
        case "${PROFILE}" in
            cpp-dev)  INSTALL_CONAN=true; INSTALL_VSCODE=true; INSTALL_SQLITE=true; INSTALL_ZLIB=true ;;
            devops)   INSTALL_CONAN=true; INSTALL_SQLITE=true ;;
            minimal)  ;;
            full)
                INSTALL_CONAN=true; INSTALL_VSCODE=true
                INSTALL_SQLITE=true; INSTALL_MATLAB=true; INSTALL_ZLIB=true
                INSTALL_GRPC=true   # Windows: default v143 Release; Linux: RHEL/Rocky 8/9/10 package
                [[ "${OS}" == "windows" ]] && { INSTALL_SERVY=true; INSTALL_WINLIBS=true; }
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
# Step 1: prebuilt submodule
# ---------------------------------------------------------------------------
echo "  [1/13] Checking prebuilt submodule..."
_prebuilt_populated() {
    # "populated" means the directory exists and contains at least one file
    [[ -d "${REPO_ROOT}/prebuilt" ]] && \
        find "${REPO_ROOT}/prebuilt" -maxdepth 2 -type f 2>/dev/null | grep -q .
}
if _prebuilt_populated; then
    echo "  [OK]  prebuilt already present."
elif git -C "${REPO_ROOT}" submodule status prebuilt 2>/dev/null | grep -q "^[^-]"; then
    echo "  [OK]  prebuilt submodule already initialized."
else
    # prebuilt is absent — only try git fetch when NOT air-gapped.
    # In an air-gapped environment the repo admin must pre-populate prebuilt/
    # before running this script; we warn and continue rather than failing hard.
    if [[ "${GIT_ALLOW_PROTOCOL:-}" == "" ]] && git ls-remote --exit-code \
            "$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null)" &>/dev/null 2>&1; then
        im_progress_start "Initialising prebuilt submodule"
        git -C "${REPO_ROOT}" submodule update --init --recursive prebuilt
        im_progress_stop "Submodule ready"
    else
        echo "  [!!]  prebuilt/ not found and network is unavailable (air-gap mode)."
        echo "        Continuing without prebuilt — tools that need it will fail gracefully."
        echo "        To fix: populate prebuilt/ before running this script in air-gapped environments."
    fi
fi

# ---------------------------------------------------------------------------
# Step 2: tools/toolchains/clang
# ---------------------------------------------------------------------------
echo ""
echo "  [2/13] Installing tools/toolchains/llvm (required)..."
_run_bootstrap "clang-llvm" \
    "${REPO_ROOT}/tools/toolchains/llvm/setup.sh"

# Make LLVM tools available for subsequent steps (e.g. style-formatter needs clang-format)
export PATH="${INSTALL_PREFIX_OVERRIDE}/clang-llvm/bin:${PATH}"

# ---------------------------------------------------------------------------
# Step 3: cmake
# ---------------------------------------------------------------------------
echo ""
echo "  [3/13] Installing cmake 4.3.1 (required)..."
_run_bootstrap "cmake" \
    "${REPO_ROOT}/tools/build-tools/cmake/setup.sh"

# Make cmake available for subsequent steps (e.g. the zlib source build needs it)
export PATH="${INSTALL_PREFIX_OVERRIDE}/cmake/bin:${PATH}"

# ---------------------------------------------------------------------------
# Step 4: python
# ---------------------------------------------------------------------------
echo ""
echo "  [4/13] Installing python 3.14.4 (required)..."
_run_bootstrap "python" \
    "${REPO_ROOT}/tools/languages/python/setup.sh"

# Make python available for subsequent steps (e.g. lcov's genhtml tooling)
export PATH="${INSTALL_PREFIX_OVERRIDE}/python/bin:${PATH}"

# ---------------------------------------------------------------------------
# Step 5: lcov (Linux only)
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]]; then
    echo ""
    echo "  [5/13] Installing lcov 2.5 (required on Linux)..."
    _run_bootstrap "lcov" \
        "${REPO_ROOT}/tools/toolchains/lcov/setup.sh"
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
_CLANG_FORMAT="${INSTALL_PREFIX_OVERRIDE}/clang-llvm/bin/clang-format"
if [[ ! -x "${_CLANG_FORMAT}" ]] || ! "${_CLANG_FORMAT}" --version &>/dev/null; then
    echo "  [--]  Skipped: style-formatter (clang-format not compatible with this system's runtime libraries)"
    SKIPPED_TOOLS+=("style-formatter (runtime library incompatible)")
elif ! git -C "${REPO_ROOT}" rev-parse --git-dir &>/dev/null; then
    # The style formatter installs a git pre-commit hook, which only makes sense
    # inside a git repository. Skip cleanly when run outside one (e.g. an
    # unpacked source tarball or a container with .git excluded).
    echo "  [--]  Skipped: style-formatter (not inside a git repository)"
    SKIPPED_TOOLS+=("style-formatter (no git repository)")
else
    _run_bootstrap_no_prefix "style-formatter" \
        "${REPO_ROOT}/tools/toolchains/llvm/style-formatter/bootstrap.sh"
fi
unset _CLANG_FORMAT

# ---------------------------------------------------------------------------
# Step 7: servy (optional, Windows only)
# ---------------------------------------------------------------------------
echo ""
echo "  [7/13] Servy 7.9 (optional, Windows only)..."
if [[ "${INSTALL_SERVY}" == "true" ]]; then
    _run_setup "servy" "${REPO_ROOT}/tools/dev-tools/servy/setup.sh"
else
    echo "  [--]  Skipped: servy"
    SKIPPED_TOOLS+=("servy")
fi

# ---------------------------------------------------------------------------
# Step 8: conan (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [8/13] Conan 2.30.0 (optional)..."
if [[ "${INSTALL_CONAN}" == "true" ]]; then
    _run_setup "conan" "${REPO_ROOT}/tools/dev-tools/conan/setup.sh"
else
    echo "  [--]  Skipped: conan"
    SKIPPED_TOOLS+=("conan")
fi

# ---------------------------------------------------------------------------
# Step 9: zlib (optional, both platforms — vendored source, CMake build)
# ---------------------------------------------------------------------------
echo ""
echo "  [9/13] zlib 1.3.2 (optional)..."
if [[ "${INSTALL_ZLIB}" == "true" ]]; then
    _run_setup "zlib" "${REPO_ROOT}/tools/lib/zlib/setup.sh"
else
    echo "  [--]  Skipped: zlib"
    SKIPPED_TOOLS+=("zlib")
fi

# ---------------------------------------------------------------------------
# Step 10: tools/dev-tools/vscode-extensions (optional)
# ---------------------------------------------------------------------------
echo ""
echo "  [10/13] VS Code extensions (optional)..."
if [[ "${INSTALL_VSCODE}" == "true" ]]; then
    if ! command -v code &>/dev/null; then
        echo "  [--]  Skipped: dev-tools/vscode-extensions (VS Code not installed)"
        SKIPPED_TOOLS+=("dev-tools/vscode-extensions (code not found)")
    else
        _run_bootstrap_no_prefix "dev-tools/vscode-extensions" \
            "${REPO_ROOT}/tools/dev-tools/vscode-extensions/setup.sh"
    fi
else
    echo "  [--]  Skipped: tools/dev-tools/vscode-extensions"
    SKIPPED_TOOLS+=("tools/dev-tools/vscode-extensions")
fi

# ---------------------------------------------------------------------------
# Step 10: optional platform tools (Windows only)
# ---------------------------------------------------------------------------
echo ""
echo "  [11/13] Optional platform tools..."
if [[ "${OS}" == "windows" ]]; then
    if [[ "${INSTALL_WINLIBS}" == "true" ]]; then
        _run_bootstrap_winlibs "winlibs-gcc-ucrt" \
            "${REPO_ROOT}/tools/toolchains/gcc/windows/setup.sh"
    else
        echo "  [--]  Skipped: winlibs-gcc-ucrt"
        SKIPPED_TOOLS+=("winlibs-gcc-ucrt")
    fi

    if [[ "${INSTALL_GRPC}" == "true" ]]; then
        _run_bootstrap "grpc-${GRPC_VERSION}-msvc${GRPC_TOOLSET#v}" \
            "${REPO_ROOT}/tools/frameworks/grpc/setup.sh" \
            "--toolset" "${GRPC_TOOLSET}"
    else
        echo "  [--]  Skipped: tools/frameworks/grpc"
        SKIPPED_TOOLS+=("tools/frameworks/grpc")
    fi
else
    echo "  [--]  winlibs-gcc-ucrt  -- skipped (Windows only)"
    SKIPPED_TOOLS+=("winlibs-gcc-ucrt (Windows only)")

    # gRPC ships a RHEL/Rocky 8/9/10 (x86_64) static-runtime package for Linux targets.
    if [[ "${INSTALL_GRPC}" == "true" ]]; then
        _run_bootstrap "grpc-${GRPC_VERSION}-linux" \
            "${REPO_ROOT}/tools/frameworks/grpc/setup.sh" \
            "--platform" "linux"
    else
        echo "  [--]  Skipped: tools/frameworks/grpc"
        SKIPPED_TOOLS+=("tools/frameworks/grpc")
    fi
fi

# ---------------------------------------------------------------------------
# Step 11: SQLite CLI (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [12/13] SQLite 3.53.0 CLI (optional)..."
if [[ "${INSTALL_SQLITE}" == "true" ]]; then
    _run_setup "sqlite" "${REPO_ROOT}/tools/dev-tools/sqlite/setup.sh"
else
    echo "  [--]  Skipped: sqlite"
    SKIPPED_TOOLS+=("sqlite")
fi

# ---------------------------------------------------------------------------
# Step 12: MATLAB verification (optional, both platforms)
# ---------------------------------------------------------------------------
echo ""
echo "  [13/13] MATLAB toolbox verification (optional)..."
if [[ "${INSTALL_MATLAB}" == "true" ]]; then
    _run_bootstrap_no_prefix "matlab" \
        "${REPO_ROOT}/tools/dev-tools/matlab/setup.sh"
else
    echo "  [--]  Skipped: matlab"
    SKIPPED_TOOLS+=("matlab")
fi

# ---------------------------------------------------------------------------
# Generate env.sh
# ---------------------------------------------------------------------------
ENV_DIR="${INSTALL_PREFIX_OVERRIDE}"
ENV_FILE="${ENV_DIR}/env.sh"
mkdir -p "${ENV_DIR}"
cat > "${ENV_FILE}" << 'ENVSH'
#!/usr/bin/env bash
# airgap-cpp-devkit — source this file or add to ~/.bashrc
_devkit_prefix="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _d in "$_devkit_prefix"/*/bin "$_devkit_prefix"/*/*/bin; do
    [[ -d "$_d" ]] && export PATH="$_d:$PATH"
done
# Expose vendored Perl libs so lcov/genhtml can load their modules
for _plib in "$_devkit_prefix/lcov/lib" "$_devkit_prefix/lcov/lib/lcov"; do
    [[ -d "$_plib" ]] && export PERL5LIB="${_plib}${PERL5LIB:+:${PERL5LIB}}"
done
unset _devkit_prefix _d _plib
ENVSH
chmod +x "${ENV_FILE}"

# ---------------------------------------------------------------------------
# Wire env.sh into ~/.bashrc
# ---------------------------------------------------------------------------
echo ""
echo "  Wiring env.sh into ~/.bashrc..."
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
echo "  To manage tools visually: bash scripts/launch.sh"
echo "    Opens http://127.0.0.1:9090 -- dashboard, install, logs."
echo ""