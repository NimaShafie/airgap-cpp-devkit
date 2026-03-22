#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/install-mode.sh
#
# PURPOSE: Shared library sourced by all airgap-cpp-devkit bootstrap/setup
#          scripts. Detects whether the current user has admin/root privileges,
#          selects appropriate system-wide or per-user install paths, and
#          provides helpers for install receipt and log file generation.
#
# USAGE:
#   Source this file early in any bootstrap/setup script:
#     source "${REPO_ROOT}/scripts/install-mode.sh"
#     install_mode_init "<tool-name>" "<tool-version>"
#
#   Then use the exported variables:
#     INSTALL_MODE       — "admin" or "user"
#     INSTALL_PREFIX     — root install directory
#     INSTALL_BIN_DIR    — where binaries go
#     INSTALL_LOG_FILE   — full path to the timestamped log file
#     INSTALL_RECEIPT    — full path to the install receipt file
#
#   And the helpers:
#     install_mode_print_header    — print the mode banner
#     install_receipt_write        — write the receipt file
#     install_log_capture_start    — tee all output to log file
#     install_env_register         — register bin dir in shared env.sh
#     im_progress_start            — start a progress ticker
#     im_progress_stop             — stop the progress ticker
#
# INSTALL PATHS:
#
#   Admin (system-wide):
#     Windows : C:\Program Files\airgap-cpp-devkit\<tool>\
#     Linux   : /opt/airgap-cpp-devkit/<tool>/
#
#   User (per-user, no admin required):
#     Windows : %LOCALAPPDATA%\airgap-cpp-devkit\<tool>\
#               (~/.local/share equivalent in Git Bash)
#     Linux   : ~/.local/share/airgap-cpp-devkit/<tool>/
#
#   Log files (always written regardless of install mode):
#     Windows : %TEMP%\airgap-cpp-devkit\logs\
#               (~/AppData/Local/Temp/airgap-cpp-devkit/logs/ in Git Bash)
#     Linux   : /var/log/airgap-cpp-devkit/
#               (falls back to ~/airgap-cpp-devkit-logs/ if not writable)
# =============================================================================

# Guard against double-sourcing
[[ -n "${_INSTALL_MODE_LOADED:-}" ]] && return 0
_INSTALL_MODE_LOADED=1

# ---------------------------------------------------------------------------
# Internal: detect OS
# ---------------------------------------------------------------------------
_im_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)                echo "linux"   ;;
        Darwin*)               echo "macos"   ;;
        *)                     echo "unknown" ;;
    esac
}

# ---------------------------------------------------------------------------
# Internal: test whether we can write to a system path
# ---------------------------------------------------------------------------
_im_can_write_system() {
    local test_path="$1"
    mkdir -p "${test_path}" 2>/dev/null || true
    local test_file="${test_path}/.airgap_write_test_$$"
    if touch "${test_file}" 2>/dev/null; then
        rm -f "${test_file}" 2>/dev/null || true
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Internal: resolve Windows %LOCALAPPDATA% in Git Bash
# ---------------------------------------------------------------------------
_im_localappdata() {
    if [[ -n "${LOCALAPPDATA:-}" ]]; then
        cygpath -u "${LOCALAPPDATA}" 2>/dev/null || \
            printf '%s' "${LOCALAPPDATA}" | sed 's|\\|/|g; s|^C:|/c|i'
    else
        echo "${HOME}/AppData/Local"
    fi
}

# ---------------------------------------------------------------------------
# Internal: resolve Windows %TEMP% in Git Bash
# ---------------------------------------------------------------------------
_im_temp_dir() {
    local os="$(_im_os)"
    if [[ "${os}" == "windows" ]]; then
        if [[ -n "${TEMP:-}" ]]; then
            cygpath -u "${TEMP}" 2>/dev/null || \
                printf '%s' "${TEMP}" | sed 's|\\|/|g; s|^C:|/c|i'
        else
            echo "${HOME}/AppData/Local/Temp"
        fi
    else
        echo "/tmp"
    fi
}

# ---------------------------------------------------------------------------
# Internal: print a box content line, exactly fitting the 68-column box.
#
# The box looks like:  ║<66 visual columns>║
# Each ║ is 3 bytes but 1 visual column.
#
# Strategy: measure the visual width of the string (accounting for multi-byte
# Unicode), truncate to 66 visual columns with … if needed, then pad with
# spaces to reach exactly 66 visual columns, then wrap with ║...║.
#
# _im_visual_len <string>  — returns visual column count
# _im_box_line   <string>  — prints ║<string padded to 66 cols>║
# ---------------------------------------------------------------------------
_im_visual_len() {
    local str="$1"
    # Replace each multi-byte Unicode char (non-ASCII) with a single char
    # to get visual width. We do this by stripping bytes and counting chars.
    local stripped
    stripped="$(printf '%s' "${str}" | sed 's/[^\x00-\x7F]/?/g')"
    # Each non-ASCII sequence was replaced by one '?' = 1 visual col
    echo "${#stripped}"
}

_im_box_line() {
    local str="$1"
    local box_width=66
    local vlen
    vlen="$(_im_visual_len "${str}")"

    # Truncate if too long
    if (( vlen > box_width )); then
        # Need to truncate. Walk chars until visual width hits box_width-1.
        local result="" i=0 char vl_so_far=0
        while IFS= read -r -n1 char; do
            local clen
            clen="$(_im_visual_len "${char}")"
            if (( vl_so_far + clen + 1 > box_width )); then
                result+="…"
                break
            fi
            result+="${char}"
            (( vl_so_far += clen ))
        done < <(printf '%s' "${str}")
        str="${result}"
        vlen="$(_im_visual_len "${str}")"
    fi

    # Pad with spaces to reach exactly box_width visual columns
    local pad=$(( box_width - vlen ))
    local padding
    padding="$(printf '%*s' "${pad}" '')"

    printf '║%s%s║\n' "${str}" "${padding}"
}

# ---------------------------------------------------------------------------
# install_mode_init <tool_name> <tool_version>
# ---------------------------------------------------------------------------
install_mode_init() {
    local tool_name="${1:-unknown}"
    local tool_version="${2:-unknown}"
    local os
    os="$(_im_os)"
    local timestamp
    timestamp="$(date +"%Y%m%d-%H%M%S")"

    local sys_prefix user_prefix
    case "${os}" in
        windows)
            local pf
            pf="$( cygpath -u "${PROGRAMFILES:-/c/Program Files}" 2>/dev/null \
                   || echo "/c/Program Files" )"
            sys_prefix="${pf}/airgap-cpp-devkit/${tool_name}"
            user_prefix="$(_im_localappdata)/airgap-cpp-devkit/${tool_name}"
            ;;
        linux|macos)
            sys_prefix="/opt/airgap-cpp-devkit/${tool_name}"
            user_prefix="${HOME}/.local/share/airgap-cpp-devkit/${tool_name}"
            ;;
        *)
            sys_prefix="/opt/airgap-cpp-devkit/${tool_name}"
            user_prefix="${HOME}/.local/share/airgap-cpp-devkit/${tool_name}"
            ;;
    esac

    if _im_can_write_system "${sys_prefix}"; then
        export INSTALL_MODE="admin"
        export INSTALL_PREFIX="${sys_prefix}"
    else
        export INSTALL_MODE="user"
        export INSTALL_PREFIX="${user_prefix}"
    fi

    export INSTALL_BIN_DIR="${INSTALL_PREFIX}/bin"
    export INSTALL_TOOL_NAME="${tool_name}"
    export INSTALL_TOOL_VERSION="${tool_version}"
    export INSTALL_TIMESTAMP="${timestamp}"
    export INSTALL_OS="${os}"

    local log_base
    case "${os}" in
        windows)
            log_base="$(_im_temp_dir)/airgap-cpp-devkit/logs"
            ;;
        linux|macos)
            if _im_can_write_system "/var/log/airgap-cpp-devkit"; then
                log_base="/var/log/airgap-cpp-devkit"
            else
                log_base="${HOME}/airgap-cpp-devkit-logs"
            fi
            ;;
        *)
            log_base="${HOME}/airgap-cpp-devkit-logs"
            ;;
    esac
    mkdir -p "${log_base}" 2>/dev/null || true
    export INSTALL_LOG_DIR="${log_base}"
    export INSTALL_LOG_FILE="${log_base}/${tool_name}-${timestamp}.log"
    export INSTALL_RECEIPT="${INSTALL_PREFIX}/INSTALL_RECEIPT.txt"

    install_mode_print_header
}

# ---------------------------------------------------------------------------
# install_mode_print_header
# ---------------------------------------------------------------------------
install_mode_print_header() {
    local mode_label scope_label mode_icon
    if [[ "${INSTALL_MODE}" == "admin" ]]; then
        mode_label="SYSTEM-WIDE  (admin / root)"
        scope_label="ALL users on this machine"
        mode_icon="[OK]"
    else
        mode_label="CURRENT USER ONLY  (no admin rights detected)"
        scope_label="THIS user only — other users will NOT have access"
        mode_icon="[!!]"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    _im_box_line "  airgap-cpp-devkit — Install Mode"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    _im_box_line "  Tool        : ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION}"
    _im_box_line "  Mode        : ${mode_icon}  ${mode_label}"
    _im_box_line "  Install dir : ${INSTALL_PREFIX}"
    _im_box_line "  Available to: ${scope_label}"
    _im_box_line "  Log file    : ${INSTALL_LOG_FILE}"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "${INSTALL_MODE}" == "user" ]]; then
        echo "  [!!] NOTE: Running without admin/root privileges."
        echo "     Tools will be installed to your personal directory only."
        echo "     To install system-wide for all users, re-run as admin/root:"
        case "${INSTALL_OS}" in
            windows) echo "       Right-click Git Bash -> 'Run as administrator'" ;;
            linux)   echo "       sudo bash $(basename "$0")" ;;
        esac
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# install_mode_print_footer <status> [<label:path> ...]
# ---------------------------------------------------------------------------
install_mode_print_footer() {
    local status="${1:-success}"
    shift || true

    local status_label status_icon
    if [[ "${status}" == "success" ]]; then
        status_label="SUCCESS"
        status_icon="[OK]"
    else
        status_label="FAILED"
        status_icon="[!!]"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    _im_box_line "  ${status_icon}  ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION} — ${status_label}"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    _im_box_line "  Install mode : ${INSTALL_MODE}"
    _im_box_line "  Install path : ${INSTALL_PREFIX}"
    for pair in "$@"; do
        local label="${pair%%:*}"
        local path="${pair#*:}"
        _im_box_line "  ${label} : ${path}"
    done
    echo "╠══════════════════════════════════════════════════════════════════╣"
    _im_box_line "  Log     : ${INSTALL_LOG_FILE}"
    _im_box_line "  Receipt : ${INSTALL_RECEIPT}"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "${INSTALL_MODE}" == "user" ]]; then
        echo "  [!!] Installed to user path — NOT available to other users."
        echo "       Re-run as admin/root to install system-wide."
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# install_receipt_write <status> [<label:path> ...]
# ---------------------------------------------------------------------------
install_receipt_write() {
    local status="${1:-success}"
    shift || true

    mkdir -p "${INSTALL_PREFIX}" 2>/dev/null || true

    {
        echo "airgap-cpp-devkit — Install Receipt"
        echo "===================================="
        echo ""
        echo "Tool         : ${INSTALL_TOOL_NAME}"
        echo "Version      : ${INSTALL_TOOL_VERSION}"
        echo "Status       : ${status}"
        echo "Install mode : ${INSTALL_MODE}"
        echo "Install path : ${INSTALL_PREFIX}"
        echo "Date         : $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "User         : $(whoami 2>/dev/null || echo unknown)"
        echo "Hostname     : $(hostname 2>/dev/null || echo unknown)"
        echo "OS           : ${INSTALL_OS}"
        echo "Log file     : ${INSTALL_LOG_FILE}"
        echo ""
        if [[ $# -gt 0 ]]; then
            echo "Installed binaries:"
            for pair in "$@"; do
                local label="${pair%%:*}"
                local path="${pair#*:}"
                echo "  ${label} : ${path}"
                if [[ -f "${path}" || -f "${path}.exe" ]]; then
                    local actual_path="${path}"
                    [[ -f "${path}.exe" ]] && actual_path="${path}.exe"
                    local sha256
                    sha256="$(sha256sum "${actual_path}" 2>/dev/null | awk '{print $1}' || echo "unavailable")"
                    echo "    SHA256 : ${sha256}"
                fi
            done
        fi
        echo ""
        echo "Available to all users : $([[ "${INSTALL_MODE}" == "admin" ]] && echo "YES" || echo "NO — current user only")"
        echo ""
        if [[ "${INSTALL_MODE}" == "user" ]]; then
            echo "WARNING: This installation is only accessible to the current user."
            echo "         To make available system-wide, re-run as admin/root."
        fi
    } > "${INSTALL_RECEIPT}" 2>/dev/null || {
        echo "[install-mode] WARNING: Could not write receipt to ${INSTALL_RECEIPT}" >&2
    }

    echo "[install-mode] Receipt written: ${INSTALL_RECEIPT}"
}

# ---------------------------------------------------------------------------
# install_log_capture_start
# ---------------------------------------------------------------------------
install_log_capture_start() {
    mkdir -p "${INSTALL_LOG_DIR}" 2>/dev/null || true

    {
        echo "airgap-cpp-devkit — Install Log"
        echo "================================"
        echo "Tool      : ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION}"
        echo "Mode      : ${INSTALL_MODE}"
        echo "Prefix    : ${INSTALL_PREFIX}"
        echo "Date      : $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "User      : $(whoami 2>/dev/null || echo unknown)"
        echo "Hostname  : $(hostname 2>/dev/null || echo unknown)"
        echo "================================"
        echo ""
    } >> "${INSTALL_LOG_FILE}" 2>/dev/null || true

    exec > >(tee -a "${INSTALL_LOG_FILE}") 2>&1

    echo "[install-mode] Logging to: ${INSTALL_LOG_FILE}"
    echo ""
}

# ---------------------------------------------------------------------------
# im_progress_start <message>
#
# Prints a status line and starts a background ticker that updates a
# single line in-place every second, showing elapsed time.
# Call im_progress_stop when the operation completes.
#
# Usage:
#   im_progress_start "Extracting archive"
#   do_slow_thing
#   im_progress_stop "Done"
# ---------------------------------------------------------------------------
_IM_PROGRESS_PID=""

im_progress_start() {
    local msg="${1:-Working}"
    local start_time
    start_time="$(date +%s)"

    # Print initial line (no newline so we can overwrite it)
    printf "\r  [....] %s" "${msg}"

    # Spinner chars
    local spin='|/-\'

    (
        local i=0
        while true; do
            local now
            now="$(date +%s)"
            local elapsed=$(( now - start_time ))
            local mins=$(( elapsed / 60 ))
            local secs=$(( elapsed % 60 ))
            local frame="${spin:$(( i % 4 )):1}"
            printf "\r  [%s] %s  (%02d:%02d elapsed)" \
                "${frame}" "${msg}" "${mins}" "${secs}"
            (( i++ )) || true
            sleep 1
        done
    ) &
    _IM_PROGRESS_PID=$!
    # Suppress job control output
    disown "${_IM_PROGRESS_PID}" 2>/dev/null || true
}

im_progress_stop() {
    local final_msg="${1:-Done}"
    if [[ -n "${_IM_PROGRESS_PID}" ]]; then
        kill "${_IM_PROGRESS_PID}" 2>/dev/null || true
        wait "${_IM_PROGRESS_PID}" 2>/dev/null || true
        _IM_PROGRESS_PID=""
    fi
    # Clear the spinner line and print final status
    printf "\r  [OK]  %s\n" "${final_msg}"
}

# ---------------------------------------------------------------------------
# install_env_register <bin_dir>
#
# Appends the given bin_dir to the shared airgap-cpp-devkit env.sh so all
# tools are on PATH after a single source. The env file sits one level above
# the tool install dir:
#   admin  Linux   : /opt/airgap-cpp-devkit/env.sh
#   admin  Windows : /c/Program Files/airgap-cpp-devkit/env.sh
#   user   Linux   : ~/.local/share/airgap-cpp-devkit/env.sh
#   user   Windows : %LOCALAPPDATA%/airgap-cpp-devkit/env.sh
#
# The install.sh orchestrator wires this file into ~/.bashrc once.
# ---------------------------------------------------------------------------
install_env_register() {
    local bin_dir="$1"
    local env_dir
    env_dir="$(dirname "${INSTALL_PREFIX}")"
    local env_file="${env_dir}/env.sh"

    mkdir -p "${env_dir}" 2>/dev/null || true

    if [[ ! -f "${env_file}" ]]; then
        {
            echo "# airgap-cpp-devkit — PATH environment"
            echo "# Auto-generated by install-mode.sh — do not edit manually."
            echo "# Source this file from ~/.bashrc to put all tools on PATH:"
            echo "#   source \"${env_file}\""
            echo ""
        } > "${env_file}"
    fi

    local export_line="export PATH=\"${bin_dir}:\${PATH}\""
    if ! grep -qF "${bin_dir}" "${env_file}" 2>/dev/null; then
        echo "${export_line}" >> "${env_file}"
        echo "[install-mode] Registered PATH: ${bin_dir} -> ${env_file}"
    else
        echo "[install-mode] PATH already registered: ${bin_dir}"
    fi

    echo "${env_file}"
}