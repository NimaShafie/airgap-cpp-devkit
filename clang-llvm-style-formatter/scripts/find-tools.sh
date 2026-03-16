#!/usr/bin/env bash
# =============================================================================
# find-tools.sh — Locate clang-format and clang-tidy on the current system.
#
# Sourced by the pre-commit hook and verify-tools.sh.
# Updates CLANG_FORMAT_BIN / CLANG_TIDY_BIN if the current values are not
# resolvable.
#
# Search order:
#   1. Value already set in hooks.conf / environment (explicit override)
#   2. Plain name on PATH
#   3. Versioned names on PATH  (clang-format-18, -17, -16 …)
#   4. Known install locations — Windows (VS 2017/2019/2022 + standalone LLVM)
#   5. Known install locations — RHEL 8 / Linux (dnf module, SCL, user-local)
#
# This file intentionally does NOT abort on failure (no set -e).
# The calling script is responsible for checking the result and erroring.
# =============================================================================

_detect_os_for_find() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)                echo "linux"   ;;
        Darwin*)               echo "macos"   ;;
        *)                     echo "unknown" ;;
    esac
}

_FIND_OS="$(_detect_os_for_find)"

_find_clang_tool() {
    local tool="$1"

    # 0. Vendored build inside the submodule — highest priority
    #    Produced by build-clang-format.sh; works with zero PATH changes.
    local _self_dir
    _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || true)"
    local _submodule_root
    _submodule_root="$(cd "${_self_dir}/.." && pwd 2>/dev/null || true)"
    # pip venv (preferred)
    for _bundled in         "${_submodule_root}/.venv/Scripts/${tool}.exe"         "${_submodule_root}/.venv/bin/${tool}"; do
        [[ -x "${_bundled}" ]] && { echo "${_bundled}"; return 0; }
    done
    # clang-llvm-source-build bin/ fallback
    for _bundled in         "${_submodule_root}/../clang-llvm-source-build/bin/windows/${tool}.exe"         "${_submodule_root}/../clang-llvm-source-build/bin/linux/${tool}"; do
        [[ -x "${_bundled}" ]] && { echo "${_bundled}"; return 0; }
    done

    # 1. Already explicit and found via current value in env
    local env_var="${tool//-/_}_BIN"
    local current_val="${!env_var:-${tool}}"
    if command -v "${current_val}" &>/dev/null; then
        echo "${current_val}"
        return 0
    fi

    # 2. Plain name on PATH
    if command -v "${tool}" &>/dev/null; then
        echo "${tool}"
        return 0
    fi

    # 3. Versioned suffixes on PATH — newest first
    for ver in 18 17 16 15 14 13 12; do
        if command -v "${tool}-${ver}" &>/dev/null; then
            echo "${tool}-${ver}"
            return 0
        fi
    done

    # 4. Windows heuristic paths
    if [[ "${_FIND_OS}" == "windows" ]]; then
        local win_candidates=()

        # Official standalone LLVM installer
        win_candidates+=(
            "/c/Program Files/LLVM/bin/${tool}.exe"
            "/c/Program Files (x86)/LLVM/bin/${tool}.exe"
        )

        # Visual Studio bundled LLVM — all supported combinations
        # Note: x64/bin is the 64-bit toolchain; bin/ is 32-bit (fallback)
        for vs_year in 2022 2019 2017; do
            for edition in Enterprise Professional Community; do
                win_candidates+=(
                    "/c/Program Files/Microsoft Visual Studio/${vs_year}/${edition}/VC/Tools/Llvm/x64/bin/${tool}.exe"
                    "/c/Program Files/Microsoft Visual Studio/${vs_year}/${edition}/VC/Tools/Llvm/bin/${tool}.exe"
                    "/c/Program Files (x86)/Microsoft Visual Studio/${vs_year}/${edition}/VC/Tools/Llvm/bin/${tool}.exe"
                )
            done
            # Build Tools variant (no full VS, used on CI agents)
            win_candidates+=(
                "/c/Program Files (x86)/Microsoft Visual Studio/${vs_year}/BuildTools/VC/Tools/Llvm/x64/bin/${tool}.exe"
                "/c/Program Files (x86)/Microsoft Visual Studio/${vs_year}/BuildTools/VC/Tools/Llvm/bin/${tool}.exe"
            )
        done

        for p in "${win_candidates[@]}"; do
            if [[ -x "${p}" ]]; then
                echo "${p}"
                return 0
            fi
        done
    fi

    # 5. RHEL 8 / Linux heuristic paths
    if [[ "${_FIND_OS}" == "linux" || "${_FIND_OS}" == "unknown" ]]; then
        local linux_candidates=()

        # Standard system paths
        linux_candidates+=(
            "/usr/bin/${tool}"
            "/usr/local/bin/${tool}"
        )

        # Versioned system packages (Debian/Ubuntu style, useful if devs run Linux desktop)
        for ver in 18 17 16 15 14 13; do
            linux_candidates+=(
                "/usr/bin/${tool}-${ver}"
                "/usr/lib/llvm-${ver}/bin/${tool}"
            )
        done

        # RHEL 8 dnf module / SCL paths
        for ver in 18 17 16 15 14 13; do
            linux_candidates+=(
                "/opt/rh/llvm-toolset-${ver}/root/usr/bin/${tool}"
            )
        done
        linux_candidates+=(
            "/opt/rh/llvm-toolset/root/usr/bin/${tool}"
        )

        # User-local extraction (no-sudo rpm2cpio method, documented in
        # docs/llvm-install-guide.md)
        linux_candidates+=(
            "${HOME}/llvm-local/bin/${tool}"
            "/opt/llvm/bin/${tool}"
        )

        for p in "${linux_candidates[@]}"; do
            if [[ -x "${p}" ]]; then
                echo "${p}"
                return 0
            fi
        done
    fi

    return 1
}

# Resolve and export — only overwrite if a better path was found
_resolved_format="$(_find_clang_tool "clang-format" 2>/dev/null || true)"
_resolved_tidy="$(_find_clang_tool "clang-tidy"   2>/dev/null || true)"

[[ -n "${_resolved_format}" ]] && CLANG_FORMAT_BIN="${_resolved_format}"
[[ -n "${_resolved_tidy}"   ]] && CLANG_TIDY_BIN="${_resolved_tidy}"

export CLANG_FORMAT_BIN CLANG_TIDY_BIN