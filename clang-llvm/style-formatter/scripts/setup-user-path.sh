#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# setup-user-path.sh — Add an LLVM bin directory to the current user's PATH
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  NOTE: This script is NOT required for the standard pip/venv install.  │
# │                                                                         │
# │  The pre-commit hook and all helper scripts (fix-format.sh, etc.)      │
# │  locate clang-format automatically via find-tools.sh, which checks     │
# │  the .venv/ directory inside the submodule without any PATH changes.   │
# │                                                                         │
# │  Use this script only if you want clang-format available on your       │
# │  system PATH for interactive use (e.g. running it manually, or         │
# │  integrating with an editor that reads PATH rather than the venv).     │
# └─────────────────────────────────────────────────────────────────────────┘
#
# No administrator or root privileges required.
#   • Windows (Git Bash / MINGW64): uses `setx` (user-scoped registry key)
#     and appends to ~/.bashrc for the current shell session.
#   • Linux (RHEL 8 / generic):     appends to ~/.bashrc and ~/.bash_profile.
#
# Usage:
#   bash scripts/setup-user-path.sh --auto           # scan known locations
#   bash scripts/setup-user-path.sh --llvm-bin /path/to/llvm/bin
#
# The script never modifies system files and never requires sudo.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
LLVM_BIN_DIR=""
AUTO_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --llvm-bin)
            LLVM_BIN_DIR="$2"; shift 2 ;;
        --auto)
            AUTO_MODE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--llvm-bin <dir>] [--auto]"
            exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)               echo "linux"   ;;
        Darwin*)              echo "macos"   ;;
        *)                    echo "unknown" ;;
    esac
}

OS="$(detect_os)"
echo "[setup-user-path] Detected OS: ${OS}"

# ---------------------------------------------------------------------------
# Auto-detect the LLVM bin directory
# ---------------------------------------------------------------------------
_auto_detect_llvm_bin() {
    # Try which first
    for tool in clang-format clang-tidy clang; do
        if command -v "${tool}" &>/dev/null; then
            local p
            p="$(dirname "$(command -v "${tool}")")"
            echo "${p}"
            return 0
        fi
    done

    # Windows: scan common install locations
    if [[ "${OS}" == "windows" ]]; then
        local win_paths=(
            "/c/Program Files/LLVM/bin"
            "/c/Program Files (x86)/LLVM/bin"
        )
        for vs_year in 2022 2019 2017; do
            for edition in Enterprise Professional Community; do
                win_paths+=("/c/Program Files/Microsoft Visual Studio/${vs_year}/${edition}/VC/Tools/Llvm/bin")
            done
            win_paths+=("/c/Program Files (x86)/Microsoft Visual Studio/${vs_year}/BuildTools/VC/Tools/Llvm/bin")
        done
        for p in "${win_paths[@]}"; do
            if [[ -x "${p}/clang-format.exe" || -x "${p}/clang-format" ]]; then
                echo "${p}"
                return 0
            fi
        done
    fi

    # Linux: SCL / opt paths
    if [[ "${OS}" == "linux" ]]; then
        for ver in 18 17 16 15 14 13; do
            for p in \
                "/usr/lib/llvm-${ver}/bin" \
                "/opt/rh/llvm-toolset-${ver}/root/usr/bin" \
                "/opt/llvm-${ver}/bin"; do
                if [[ -x "${p}/clang-format" ]]; then
                    echo "${p}"
                    return 0
                fi
            done
        done
        for p in "/usr/bin" "/usr/local/bin" "/opt/llvm/bin"; do
            if [[ -x "${p}/clang-format" ]]; then
                echo "${p}"
                return 0
            fi
        done
    fi

    return 1
}

if [[ -z "${LLVM_BIN_DIR}" ]]; then
    if [[ "${AUTO_MODE}" == "true" ]]; then
        LLVM_BIN_DIR="$(_auto_detect_llvm_bin || true)"
    fi
fi

if [[ -z "${LLVM_BIN_DIR}" ]]; then
    echo "[setup-user-path] Could not auto-detect an LLVM bin directory."
    echo "  Use: $0 --llvm-bin /path/to/llvm/bin"
    exit 0
fi

echo "[setup-user-path] LLVM bin directory: ${LLVM_BIN_DIR}"

# Convert to a Unix-style path that Bash can use, but also derive the
# Windows native path for setx on Windows.
UNIX_PATH="${LLVM_BIN_DIR}"

# Validate the directory contains at least clang-format
if [[ ! -x "${UNIX_PATH}/clang-format" && ! -x "${UNIX_PATH}/clang-format.exe" ]]; then
    echo "[setup-user-path] WARNING: clang-format not found in '${UNIX_PATH}'." >&2
    echo "                  Proceeding anyway — verify your LLVM installation."  >&2
fi

# ---------------------------------------------------------------------------
# Append to shell init files (idempotent — won't add duplicate entries)
# ---------------------------------------------------------------------------
MARKER="# clang-llvm-style-formatter PATH"

_append_to_file() {
    local file="$1"
    local line="$2"

    # Create the file if absent
    [[ -f "${file}" ]] || touch "${file}"

    if grep -qF "${MARKER}" "${file}" 2>/dev/null; then
        echo "[setup-user-path] PATH entry already present in ${file} — skipping."
    else
        printf '\n%s\nexport PATH="%s:${PATH}"\n' "${MARKER}" "${UNIX_PATH}" >> "${file}"
        echo "[setup-user-path] Added PATH entry to ${file}"
    fi
}

case "${OS}" in
    windows)
        # Bash init
        _append_to_file "${HOME}/.bashrc" "${UNIX_PATH}"

        # Windows user PATH via setx (no admin needed, user hive only)
        # Convert Unix path back to Windows native (e.g. /c/foo → C:\foo)
        WIN_PATH="$(cygpath -w "${UNIX_PATH}" 2>/dev/null || \
                    echo "${UNIX_PATH}" | sed 's|^/\([a-zA-Z]\)/|\1:\\|;s|/|\\|g')"

        echo "[setup-user-path] Registering Windows user PATH entry via setx..."
        # setx output is noisy; suppress stdout
        if setx PATH "%PATH%;${WIN_PATH}" > /dev/null 2>&1; then
            echo "[setup-user-path] Windows user PATH updated successfully."
            echo "                  Open a new Command Prompt / Git Bash to pick up the change."
        else
            echo "[setup-user-path] WARNING: setx failed. Add the following to your PATH manually:" >&2
            echo "                  ${WIN_PATH}" >&2
        fi
        ;;

    linux|macos)
        _append_to_file "${HOME}/.bashrc"       "${UNIX_PATH}"
        _append_to_file "${HOME}/.bash_profile" "${UNIX_PATH}"
        ;;

    *)
        echo "[setup-user-path] Unrecognised OS — appending to ~/.bashrc only."
        _append_to_file "${HOME}/.bashrc" "${UNIX_PATH}"
        ;;
esac

# ---------------------------------------------------------------------------
# Also export into the current shell session immediately
# ---------------------------------------------------------------------------
export PATH="${UNIX_PATH}:${PATH}"

echo ""
echo "[setup-user-path] Done."
echo "  clang-format : $(command -v clang-format 2>/dev/null || echo 'not found in current shell — open a new terminal')"
echo "  clang-tidy   : $(command -v clang-tidy   2>/dev/null || echo 'not found in current shell — open a new terminal')"
echo ""