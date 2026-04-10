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
#   Optional --prefix override (call before install_mode_init):
#     INSTALL_PREFIX_OVERRIDE="/custom/path"
#     install_mode_init "<tool-name>" "<tool-version>"
#
#   Then use the exported variables:
#     INSTALL_MODE       -- "admin", "user", or "custom"
#     INSTALL_PREFIX     -- root install directory
#     INSTALL_BIN_DIR    -- where binaries go
#     INSTALL_LOG_FILE   -- full path to the timestamped log file
#     INSTALL_RECEIPT    -- full path to the install receipt file
#
#   Helpers:
#     install_mode_print_header    -- print the mode banner
#     install_mode_print_footer    -- print the result banner
#     install_receipt_write        -- write the receipt file
#     install_log_capture_start    -- tee all output to log file
#     install_env_register         -- register bin dir in shared env.sh
#     im_progress_start <msg>      -- start elapsed-time ticker
#     im_progress_stop  <msg>      -- stop ticker, print final status
#
# INSTALL PATHS:
#   Admin  Linux   : /opt/airgap-cpp-devkit/<tool>/
#   Admin  Windows : C:\Program Files\airgap-cpp-devkit\<tool>\
#   User   Linux   : ~/.local/share/airgap-cpp-devkit/<tool>/
#   User   Windows : %LOCALAPPDATA%\airgap-cpp-devkit\<tool>\
#   Custom         : path from --prefix / INSTALL_PREFIX_OVERRIDE
#
#   Log files:
#   Windows : %TEMP%\airgap-cpp-devkit\logs\
#   Linux   : /var/log/airgap-cpp-devkit/  (falls back to ~/airgap-cpp-devkit-logs/)
# =============================================================================
[[ -n "${_INSTALL_MODE_LOADED:-}" ]] && { return 0; } 2>/dev/null || true
_INSTALL_MODE_LOADED=1

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
_im_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)                echo "linux"   ;;
        Darwin*)               echo "macos"   ;;
        *)                     echo "unknown" ;;
    esac
}

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

_im_localappdata() {
    if [[ -n "${LOCALAPPDATA:-}" ]]; then
        cygpath -u "${LOCALAPPDATA}" 2>/dev/null || \
            printf '%s' "${LOCALAPPDATA}" | sed 's|\\|/|g; s|^C:|/c|i'
    else
        echo "${HOME}/AppData/Local"
    fi
}

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
# Plain ASCII separators (used in header/footer)
# ---------------------------------------------------------------------------
_im_sep()  { printf '%s\n' "------------------------------------------------------------"; }
_im_sep2() { printf '%s\n' "============================================================"; }

# ---------------------------------------------------------------------------
# install_mode_init <tool_name> <tool_version>
# ---------------------------------------------------------------------------
install_mode_init() {
    local tool_name="${1:-unknown}"
    local tool_version="${2:-unknown}"
    shift 2 || true

    local prefix_override="${INSTALL_PREFIX_OVERRIDE:-}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix) prefix_override="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local os
    os="$(_im_os)"

    local timestamp
    timestamp="$(date +"%Y%m%d-%H%M%S")"

    local sys_prefix user_prefix
    case "${os}" in
        windows)
            local pf
            pf="$(cygpath -u "${PROGRAMFILES:-/c/Program Files}" 2>/dev/null || echo "/c/Program Files")"
            sys_prefix="${pf}/airgap-cpp-devkit/${tool_name}"
            user_prefix="$(_im_localappdata)/airgap-cpp-devkit/${tool_name}"
            ;;
        *)
            sys_prefix="/opt/airgap-cpp-devkit/${tool_name}"
            user_prefix="${HOME}/.local/share/airgap-cpp-devkit/${tool_name}"
            ;;
    esac

    if [[ -n "${prefix_override}" ]]; then
        if [[ "${prefix_override}" == "${sys_prefix}" ]] && _im_can_write_system "${sys_prefix}"; then
            export INSTALL_MODE="admin"
        elif [[ "${prefix_override}" == "${user_prefix}" ]]; then
            export INSTALL_MODE="user"
        else
            export INSTALL_MODE="custom"
        fi
        export INSTALL_PREFIX="${prefix_override}"
    elif _im_can_write_system "${sys_prefix}"; then
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
        *)
            if _im_can_write_system "/var/log/airgap-cpp-devkit"; then
                log_base="/var/log/airgap-cpp-devkit"
            else
                log_base="${HOME}/airgap-cpp-devkit-logs"
            fi
            ;;
    esac

    mkdir -p "${log_base}" 2>/dev/null || true
    export INSTALL_LOG_DIR="${log_base}"
    export INSTALL_LOG_FILE="${log_base}/${tool_name}/${tool_name}-${timestamp}.log"
    mkdir -p "$(dirname "${INSTALL_LOG_FILE}")" 2>/dev/null || true
    export INSTALL_RECEIPT="${INSTALL_PREFIX}/INSTALL_RECEIPT.txt"

    install_mode_print_header
}

# ---------------------------------------------------------------------------
# install_mode_print_header
# ---------------------------------------------------------------------------
install_mode_print_header() {
    local mode_label scope_label mode_icon
    case "${INSTALL_MODE}" in
        admin)
            mode_label="SYSTEM-WIDE  (admin / root)"
            scope_label="ALL users on this machine"
            mode_icon="[OK]"
            ;;
        custom)
            mode_label="CUSTOM PREFIX  (--prefix override)"
            scope_label="Custom path: ${INSTALL_PREFIX}"
            mode_icon="[>>]"
            ;;
        *)
            mode_label="CURRENT USER ONLY  (no admin rights detected)"
            scope_label="THIS user only"
            mode_icon="[!!]"
            ;;
    esac

    echo ""
    _im_sep2
    echo "  airgap-cpp-devkit -- Install Mode"
    _im_sep2
    echo "  Tool        : ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION}"
    echo "  Mode        : ${mode_icon}  ${mode_label}"
    echo "  Install dir : ${INSTALL_PREFIX}"
    echo "  Available to: ${scope_label}"
    echo "  Log file    : ${INSTALL_LOG_FILE}"
    _im_sep2
    echo ""

    if [[ "${INSTALL_MODE}" == "user" ]]; then
        echo "  [!!] NOTE: Running without admin/root privileges."
        echo "       Tools will be installed to your personal directory only."
        echo "       To install system-wide, re-run as admin/root:"
        case "${INSTALL_OS}" in
            windows) echo "         Right-click Git Bash -> 'Run as administrator'" ;;
            linux)   echo "         sudo bash $(basename "$0")" ;;
        esac
        echo "       Or specify a custom path:"
        echo "         bash $(basename "$0") --prefix /your/path"
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
    _im_sep2
    echo "  ${status_icon}  ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION} -- ${status_label}"
    _im_sep
    echo "  Install mode : ${INSTALL_MODE}"
    echo "  Install path : ${INSTALL_PREFIX}"
    for pair in "$@"; do
        local label="${pair%%:*}"
        local path="${pair#*:}"
        echo "  ${label} : ${path}"
    done
    _im_sep
    echo "  Log     : ${INSTALL_LOG_FILE}"
    echo "  Receipt : ${INSTALL_RECEIPT}"
    _im_sep2
    echo ""

    if [[ "${INSTALL_MODE}" == "user" ]]; then
        echo "  [!!] Installed to user path -- NOT available to other users."
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
        echo "airgap-cpp-devkit -- Install Receipt"
        echo "====================================="
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
        echo "Available to all users : $([[ "${INSTALL_MODE}" == "admin" ]] && echo "YES" || echo "NO -- current user only")"
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
        echo "airgap-cpp-devkit -- Install Log"
        echo "================================="
        echo "Tool      : ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION}"
        echo "Mode      : ${INSTALL_MODE}"
        echo "Prefix    : ${INSTALL_PREFIX}"
        echo "Date      : $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "User      : $(whoami 2>/dev/null || echo unknown)"
        echo "Hostname  : $(hostname 2>/dev/null || echo unknown)"
        echo "================================="
        echo ""
    } >> "${INSTALL_LOG_FILE}" 2>/dev/null || true
    exec > >(tee -a "${INSTALL_LOG_FILE}") 2>&1
    echo "[install-mode] Logging to: ${INSTALL_LOG_FILE}"
    echo ""
}

# ---------------------------------------------------------------------------
# im_progress_start <message>
#
# Prints a spinner that updates in-place every second with elapsed time.
# Registers an EXIT trap to guarantee the spinner is killed even if the
# calling script exits with an error (set -e / set -euo pipefail).
# Call im_progress_stop when the operation finishes normally.
# ---------------------------------------------------------------------------
_IM_PROGRESS_PID=""
_IM_PROGRESS_START_TIME=""

_im_progress_cleanup() {
    if [[ -n "${_IM_PROGRESS_PID:-}" ]]; then
        kill "${_IM_PROGRESS_PID}" 2>/dev/null || true
        wait "${_IM_PROGRESS_PID}" 2>/dev/null || true
        _IM_PROGRESS_PID=""
        # Clear the spinner line
        printf "\r%-80s\r" " " > /dev/tty 2>/dev/null || true
    fi
}

# Register cleanup on EXIT so spinner always dies with the script
trap '_im_progress_cleanup' EXIT

im_progress_start() {
    local msg="${1:-Working}"

    # Kill any previous spinner that wasn't stopped cleanly
    _im_progress_cleanup

    _IM_PROGRESS_START_TIME="$(date +%s)"

    if { true > /dev/tty; } 2>/dev/null; then
        local spin='|/-\'
        printf "  [....] %s" "${msg}" > /dev/tty
        (
            local i=0
            while true; do
                local now elapsed mins secs frame
                now="$(date +%s)"
                elapsed=$(( now - _IM_PROGRESS_START_TIME ))
                mins=$(( elapsed / 60 ))
                secs=$(( elapsed % 60 ))
                frame="${spin:$(( i % 4 )):1}"
                printf "\r  [ %s  ] %s  (%02d:%02d elapsed)" \
                    "${frame}" "${msg}" "${mins}" "${secs}" > /dev/tty
                (( i++ )) || true
                sleep 1
            done
        ) &
        _IM_PROGRESS_PID=$!
        disown "${_IM_PROGRESS_PID}" 2>/dev/null || true
    else
        _IM_PROGRESS_PID=""
        echo "  [....] ${msg}..."
    fi
}

im_progress_stop() {
    local final_msg="${1:-Done}"
    local now elapsed mins secs
    now="$(date +%s)"
    elapsed=$(( now - ${_IM_PROGRESS_START_TIME:-$(date +%s)} ))
    mins=$(( elapsed / 60 ))
    secs=$(( elapsed % 60 ))

    if [[ -n "${_IM_PROGRESS_PID:-}" ]]; then
        kill "${_IM_PROGRESS_PID}" 2>/dev/null || true
        wait "${_IM_PROGRESS_PID}" 2>/dev/null || true
        _IM_PROGRESS_PID=""
        printf "\r%-80s\r" " " > /dev/tty 2>/dev/null || true
        printf "  [OK]  %s  (%02d:%02d)\n" "${final_msg}" "${mins}" "${secs}" > /dev/tty 2>/dev/null || \
        printf "  [OK]  %s  (%02d:%02d)\n" "${final_msg}" "${mins}" "${secs}"
    else
        echo "  [OK]  ${final_msg}  ($(printf '%02d:%02d' ${mins} ${secs}))"
    fi

    _IM_PROGRESS_START_TIME=""
}

# ---------------------------------------------------------------------------
# install_env_register <bin_dir>
# ---------------------------------------------------------------------------
install_env_register() {
    local bin_dir="$1"
    local env_dir
    env_dir="$(dirname "${INSTALL_PREFIX}")"
    local env_file="${env_dir}/env.sh"

    mkdir -p "${env_dir}" 2>/dev/null || true

    if [[ ! -f "${env_file}" ]]; then
        {
            echo "# airgap-cpp-devkit -- PATH environment"
            echo "# Auto-generated by install-mode.sh -- do not edit manually."
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