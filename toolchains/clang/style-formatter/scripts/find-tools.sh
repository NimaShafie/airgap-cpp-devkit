#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# find-tools.sh — Locate clang-format and clang-tidy on the current system.
#
# Sourced by the pre-commit hook, fix-format.sh, and verify-tools.sh.
# Updates CLANG_FORMAT_BIN / CLANG_TIDY_BIN if the current values are not
# resolvable.
#
# Search order (first match wins):
#   1. Explicit path set in hooks.conf / environment (CLANG_FORMAT_BIN override)
#   2. pip venv inside the submodule  (.venv/ — standard install)
#   3. toolchains/clang-source-build bin/   (optional LLVM source build)
#   4. Plain name on PATH
#   5. Versioned names on PATH        (clang-format-18, -17, -16 …)
#   6. Known install locations — Windows (VS 2017/2019/2022 + standalone LLVM)
#   7. Known install locations — RHEL 8 / Linux (dnf module, SCL, user-local)
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

# Resolve the submodule root at source time, while BASH_SOURCE[0] is valid
# in the sourcing context. Exported so subshells spawned by $() at the
# bottom of this file (and in calling scripts) can inherit the value.
_FIND_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || true)"
_FIND_SUBMODULE_ROOT="$(cd "${_FIND_SELF_DIR}/.." && pwd 2>/dev/null || true)"
export _FIND_SUBMODULE_ROOT _FIND_OS

_find_clang_tool() {
    local tool="$1"

    # 1. Explicit override in hooks.conf or environment.
    #    If CLANG_FORMAT_BIN (or CLANG_TIDY_BIN) has been set to something
    #    other than the bare default tool name, treat it as an intentional
    #    path override and honour it before any auto-discovery.
    local env_var
    env_var="$(echo "${tool//-/_}_BIN" | tr '[:lower:]' '[:upper:]')"
    local current_val="${!env_var:-}"
    if [[ -n "${current_val}" && "${current_val}" != "${tool}" ]]; then
        if [[ -x "${current_val}" ]]; then
            echo "${current_val}"; return 0
        fi
        if command -v "${current_val}" &>/dev/null; then
            command -v "${current_val}"; return 0
        fi
        # Explicit override set but not resolvable — warn and fall through.
        echo "[find-tools] WARNING: ${env_var}='${current_val}' is set but not executable — falling back to auto-discovery." >&2
    fi

    # 2. pip venv (standard install — bootstrap.sh puts clang-format here).
    for _bundled in \
            "${_FIND_SUBMODULE_ROOT}/.venv/Scripts/${tool}.exe" \
            "${_FIND_SUBMODULE_ROOT}/.venv/bin/${tool}"; do
        [[ -x "${_bundled}" ]] && { echo "${_bundled}"; return 0; }
    done

    # 3. toolchains/clang-source-build bin/ (optional LLVM source build path).
    for _bundled in \
            "${_FIND_SUBMODULE_ROOT}/../toolchains/clang-source-build/bin/windows/${tool}.exe" \
            "${_FIND_SUBMODULE_ROOT}/../toolchains/clang-source-build/bin/linux/${tool}"; do
        [[ -x "${_bundled}" ]] && { echo "${_bundled}"; return 0; }
    done

    # 4. Plain name on PATH
    if command -v "${tool}" &>/dev/null; then
        echo "${tool}"
        return 0
    fi

    # 5. Versioned suffixes on PATH — newest first
    for ver in 18 17 16 15 14 13 12; do
        if command -v "${tool}-${ver}" &>/dev/null; then
            echo "${tool}-${ver}"
            return 0
        fi
    done

    # 6. Windows heuristic paths
    if [[ "${_FIND_OS}" == "windows" ]]; then
        local win_candidates=()

        # Official standalone LLVM installer
        win_candidates+=(
            "/c/Program Files/LLVM/bin/${tool}.exe"
            "/c/Program Files (x86)/LLVM/bin/${tool}.exe"
        )

        # Visual Studio bundled LLVM — all supported combinations
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

    # 7. RHEL 8 / Linux heuristic paths
    if [[ "${_FIND_OS}" == "linux" || "${_FIND_OS}" == "unknown" ]]; then
        local linux_candidates=()

        # Standard system paths
        linux_candidates+=(
            "/usr/bin/${tool}"
            "/usr/local/bin/${tool}"
        )

        # Versioned system packages (Debian/Ubuntu style)
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

        # User-local extraction (no-sudo rpm2cpio method)
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