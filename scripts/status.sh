#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/status.sh
#
# Shows the installation status of all airgap-cpp-devkit tools.
# Reads install receipts and verifies binaries are executable.
#
# USAGE:
#   bash scripts/status.sh
#
# Works on Windows (Git Bash / MINGW64) and Linux (RHEL 8+).
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)               OS="linux"   ;;
    *)                    OS="unknown" ;;
esac
_admin_prefix() {
    case "${OS}" in
        windows)
            local pf
            pf="$(cygpath -u "${PROGRAMFILES:-C:\\Program Files}" 2>/dev/null \
                || echo "/c/Program Files")"
            echo "${pf}/airgap-cpp-devkit"
            ;;
        linux) echo "/opt/airgap-cpp-devkit" ;;
    esac
}
_user_prefix() {
    case "${OS}" in
        windows)
            local lad
            lad="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null \
                || echo "${HOME}/AppData/Local")"
            echo "${lad}/airgap-cpp-devkit"
            ;;
        linux) echo "${HOME}/.local/share/airgap-cpp-devkit" ;;
    esac
}
ADMIN_PREFIX="$(_admin_prefix)"
USER_PREFIX="$(_user_prefix)"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"
_receipt_field() {
    local receipt="$1" field="$2"
    grep "^${field}" "${receipt}" 2>/dev/null \
        | head -1 | sed 's/^[^:]*: *//' | tr -d '\r'
}
_find_install_dir() {
    local tool="$1"
    local admin_dir="${ADMIN_PREFIX}/${tool}"
    local user_dir="${USER_PREFIX}/${tool}"
    if [[ -f "${admin_dir}/INSTALL_RECEIPT.txt" ]]; then
        echo "${admin_dir}"
    elif [[ -f "${user_dir}/INSTALL_RECEIPT.txt" ]]; then
        echo "${user_dir}"
    else
        echo ""
    fi
}
_check_bin() {
    local bin="${1%$'\r'}"
    bin="${bin% }"
    if [[ -x "${bin}" ]]; then
        printf "${GREEN}✓${RESET}"
    elif [[ -f "${bin}" ]]; then
        printf "${YELLOW}⚠ not executable${RESET}"
    else
        printf "${RED}✗ missing${RESET}"
    fi
}
_bin_version() {
    local bin="${1%$'\r'}"
    bin="${bin% }"
    if [[ -x "${bin}" ]]; then
        # clang-tidy outputs version on line 2; clang-format on line 1
        # Try both lines, pick first that has a version number
        "${bin}" --version 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+(-beta)?)?' | head -1 || echo "?"
    else
        echo "—"
    fi
}
_print_not_installed() {
    local tool="$1" hint="${2:-}"
    printf "  ${YELLOW}[–]${RESET} ${BOLD}%-22s${RESET} not installed\n" "${tool}"
    [[ -n "${hint}" ]] && printf "       hint: %s\n" "${hint}"
    echo ""
}
_print_platform_only() {
    local tool="$1" platform="$2"
    printf "  ${CYAN}[—]${RESET} ${BOLD}%-22s${RESET} %s only\n\n" "${tool}" "${platform}"
}
# Parse receipt binary section.
# Binary lines:   "  <name> : <path>"  (2-space indent)
# SHA256 lines:   "    SHA256 : <hash>" (4-space indent) — skip
# Stop at:        "Available to all users"
_print_installed() {
    local tool="$1" install_dir="$2" receipt="$3"
    local version install_mode install_date
    version="$(_receipt_field "${receipt}" "Version")"
    install_mode="$(_receipt_field "${receipt}" "Install mode")"
    install_date="$(_receipt_field "${receipt}" "Date")"
    printf "  ${GREEN}[✓]${RESET} ${BOLD}%-22s${RESET} %-8s  %-6s  %s\n" \
        "${tool}" "${version}" "${install_mode}" "${install_dir}"
    printf "       Installed : %s\n" "${install_date}"
    local in_binaries=false
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ "${line}" == "Installed binaries:" ]] && { in_binaries=true; continue; }
        [[ "${line}" == Available* ]] && break
        [[ "${in_binaries}" != true ]] && continue
        # Skip SHA256 lines (4+ spaces indent)
        [[ "${line}" =~ ^[[:space:]]{4} ]] && continue
        # Skip blank lines
        [[ -z "${line// }" ]] && continue
        # Parse: "  <name> : <path>"
        if [[ "${line}" =~ ^[[:space:]]{2}([^:]+):[[:space:]]*(.+)$ ]]; then
            local bin_name="${BASH_REMATCH[1]}"
            local bin_path="${BASH_REMATCH[2]}"
            bin_name="${bin_name%"${bin_name##*[![:space:]]}"}"
            bin_path="${bin_path%"${bin_path##*[![:space:]]}"}"
            local status ver
            status="$(_check_bin "${bin_path}")"
            ver="$(_bin_version "${bin_path}")"
            printf "       %-14s: %-12s %b  %s\n" \
                "${bin_name}" "${ver}" "${status}" "${bin_path}"
        fi
    done < "${receipt}"
    echo ""
}
_check_style_formatter() {
    local fmt_bin=""
    local candidates=(
        "${REPO_ROOT}/clang-llvm/style-formatter/.venv/bin/clang-format"
        "${REPO_ROOT}/clang-llvm/style-formatter/.venv/Lib/site-packages/clang_format/data/bin/clang-format.exe"
        "${REPO_ROOT}/clang-llvm/style-formatter/.venv/Lib/site-packages/clang_format/data/bin/clang-format"
        "${REPO_ROOT}/clang-llvm/style-formatter/.venv/Scripts/clang-format.exe"
        "${REPO_ROOT}/clang-llvm/style-formatter/.venv/Scripts/clang-format"
    )
    for c in "${candidates[@]}"; do
        [[ -x "${c}" ]] && { fmt_bin="${c}"; break; }
    done
    local hook="${REPO_ROOT}/.git/hooks/pre-commit"
    local hook_status="${RED}not installed${RESET}"
    [[ -f "${hook}" ]] && hook_status="${GREEN}installed${RESET}"
    if [[ -n "${fmt_bin}" ]]; then
        local ver
        ver="$(_bin_version "${fmt_bin}")"
        printf "  ${GREEN}[✓]${RESET} ${BOLD}%-22s${RESET} %-8s  in-repo venv\n" \
            "style-formatter" "${ver}"
        printf "       clang-format  : %-12s ${GREEN}✓${RESET}  %s\n" "${ver}" "${fmt_bin}"
        printf "       pre-commit    : %b\n" "${hook_status}"
        echo ""
    else
        _print_not_installed "style-formatter" \
            "bash clang-llvm/style-formatter/bootstrap.sh"
    fi
}
_check_cmake() {
    local install_dir
    install_dir="$(_find_install_dir "cmake")"
    if [[ -n "${install_dir}" ]]; then
        local receipt="${install_dir}/INSTALL_RECEIPT.txt"
        local version install_mode install_date
        version="$(_receipt_field "${receipt}" "Version")"
        install_mode="$(_receipt_field "${receipt}" "Install mode")"
        install_date="$(_receipt_field "${receipt}" "Date")"
        printf "  ${GREEN}[✓]${RESET} ${BOLD}%-22s${RESET} %-8s  %-6s  %s\n" \
            "cmake" "${version}" "${install_mode}" "${install_dir}"
        printf "       Installed : %s\n" "${install_date}"
        local cmake_bin=""
        for b in "${install_dir}/bin/cmake" "${install_dir}/bin/cmake.exe"; do
            [[ -f "${b}" ]] && cmake_bin="${b}" && break
        done
        if [[ -n "${cmake_bin}" ]]; then
            local status ver
            status="$(_check_bin "${cmake_bin}")"
            ver="$(_bin_version "${cmake_bin}")"
            printf "       cmake         : %-12s %b  %s\n" \
                "${ver}" "${status}" "${cmake_bin}"
        else
            printf "       cmake         : %-12s %b\n" "binary missing" "${RED}✗${RESET}"
        fi
        echo ""
    else
        _print_not_installed "cmake" "bash cmake/bootstrap.sh"
    fi
}
_check_winlibs() {
    if [[ "${OS}" != "windows" ]]; then
        _print_platform_only "winlibs-gcc-ucrt" "Windows"
        return
    fi
    local install_dir
    install_dir="$(_find_install_dir "winlibs-gcc-ucrt")"
    if [[ -n "${install_dir}" ]]; then
        _print_installed "winlibs-gcc-ucrt" "${install_dir}" \
            "${install_dir}/INSTALL_RECEIPT.txt"
        return
    fi
    local legacy="${REPO_ROOT}/prebuilt/winlibs-gcc-ucrt/toolchain/x86_64/mingw64/bin/gcc.exe"
    if [[ -x "${legacy}" ]]; then
        local ver
        ver="$(_bin_version "${legacy}")"
        printf "  ${YELLOW}[⚠]${RESET} ${BOLD}%-22s${RESET} %-8s  legacy in-repo path\n" \
            "winlibs-gcc-ucrt" "${ver}"
        printf "       gcc : %s\n\n" "${legacy}"
    else
        _print_not_installed "winlibs-gcc-ucrt" \
            "bash prebuilt/winlibs-gcc-ucrt/setup.sh"
    fi
}
_check_grpc() {
    if [[ "${OS}" != "windows" ]]; then
        _print_platform_only "grpc-source-build" "Windows"
        return
    fi
    local found=false
    for base in "${ADMIN_PREFIX}" "${USER_PREFIX}"; do
        for ver in "grpc-1.76.0" "grpc-1.78.1"; do
            local grpc_dir="${base}/${ver}"
            local plugin="${grpc_dir}/bin/grpc_cpp_plugin.exe"
            if [[ -d "${grpc_dir}" ]]; then
                local plugin_status
                plugin_status="$(_check_bin "${plugin}")"
                printf "  ${GREEN}[✓]${RESET} ${BOLD}%-22s${RESET} %-8s  %s\n" \
                    "${ver}" "" "${grpc_dir}"
                printf "       grpc_cpp_plugin: %b  %s\n\n" \
                    "${plugin_status}" "${plugin}"
                found=true
            fi
        done
    done
    if [[ "${found}" == false ]]; then
        _print_not_installed "grpc-source-build" \
            "bash grpc-source-build/setup_grpc.sh"
    fi
}
# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
printf "${BOLD}"
echo "======================================================================================================"
echo "  airgap-cpp-devkit — Installation Status"
echo "  Platform : ${OS}   Date : $(date '+%Y-%m-%d')"
echo "======================================================================================================"
printf "${RESET}"
echo ""
install_dir="$(_find_install_dir "clang-llvm")"
if [[ -n "${install_dir}" ]]; then
    _print_installed "clang-llvm" "${install_dir}" "${install_dir}/INSTALL_RECEIPT.txt"
else
    _print_not_installed "clang-llvm" "bash clang-llvm/source-build/bootstrap.sh"
fi
if [[ "${OS}" == "linux" ]]; then
    install_dir="$(_find_install_dir "lcov")"
    if [[ -n "${install_dir}" ]]; then
        _print_installed "lcov" "${install_dir}" "${install_dir}/INSTALL_RECEIPT.txt"
    else
        _print_not_installed "lcov" "bash lcov-source-build/bootstrap.sh"
    fi
else
    _print_platform_only "lcov" "Linux"
fi
_check_cmake
_check_style_formatter
_check_winlibs
_check_grpc
printf "${BOLD}"
echo "══════════════════════════════════════════════════════════════════════════════════════════════════════"
printf "${RESET}"
echo ""