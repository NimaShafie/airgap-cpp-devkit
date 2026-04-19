#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# uninstall.sh
#
# Removes installed airgap-cpp-devkit tools and cleans up PATH registration.
#
# USAGE:
#   bash uninstall.sh              # interactive — choose which tools to remove
#   bash uninstall.sh --all        # remove everything without prompting
#   bash uninstall.sh --prefix <path>   # look for installs under custom prefix
#
# OPTIONS:
#   --all              Remove all installed tools without prompting
#   --prefix <path>    Override install prefix to search
#   --dry-run          Show what would be removed without removing anything
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
REMOVE_ALL=false
DRY_RUN=false
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)       REMOVE_ALL=true; shift ;;
        --dry-run)   DRY_RUN=true; shift ;;
        --prefix)    PREFIX_OVERRIDE="$2"; shift 2 ;;
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
# Determine prefix candidates
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

# ---------------------------------------------------------------------------
# Box helpers
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
# Tool paths to search for INSTALL_RECEIPT.txt
# Option D paths (current) + legacy paths (pre-restructure) both supported
# ---------------------------------------------------------------------------
# Format: "display-label:relative/path/under/prefix"
ALL_TOOL_PATHS=(
    # Option D — current paths
    "clang-source-build:toolchains/clang/source-build"
    "clang-style-formatter:toolchains/clang/style-formatter"
    "clang-rhel8:toolchains/clang/rhel8"
    "clang-mingw:toolchains/clang/mingw"
    "gcc-windows:toolchains/gcc/windows"
    "gcc-linux-native:toolchains/gcc/linux/native"
    "gcc-linux-cross:toolchains/gcc/linux/cross"
    "cmake:build-tools/cmake"
    "lcov:build-tools/lcov"
    "python:languages/python"
    "7zip:dev-tools/7zip"
    "servy:dev-tools/servy"
    "vscode-extensions:dev-tools/vscode-extensions"
    "git-bundle:dev-tools/git-bundle"
    "grpc:frameworks/grpc"
    # Legacy paths (pre-Option D restructure) — kept for transition
    "clang-llvm:clang-llvm"
    "cmake-legacy:cmake"
    "lcov-legacy:lcov"
    "python-legacy:python"
    "7zip-legacy:7zip"
    "servy-legacy:servy"
    "winlibs-gcc-ucrt:winlibs-gcc-ucrt"
    "gcc-linux-legacy:gcc-linux"
    "gcc-toolset-legacy:gcc-toolset"
    "llvm-toolchain:llvm-toolchain"
    "grpc-legacy:grpc-source-build"
)

# ---------------------------------------------------------------------------
# Find installed tools under a prefix
# ---------------------------------------------------------------------------
_find_tools() {
    local base="$1"
    local found=()
    for entry in "${ALL_TOOL_PATHS[@]}"; do
        local label="${entry%%:*}"
        local relpath="${entry#*:}"
        local dir="${base}/${relpath}"
        if [[ -f "${dir}/INSTALL_RECEIPT.txt" ]]; then
            found+=("${label}:${dir}")
        fi
    done
    printf '%s\n' "${found[@]}"
}

# ---------------------------------------------------------------------------
# Remove a tool directory
# ---------------------------------------------------------------------------
_remove_tool() {
    local tool="$1"
    local dir="$2"
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [dry-run] Would remove: ${dir}"
        return
    fi
    echo "  [....] Removing ${tool}..."
    rm -rf "${dir}"
    echo "  [OK]  Removed: ${dir}"
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
_box_top
_box_line "  airgap-cpp-devkit — Uninstall"
_box_mid
_box_line "  Platform : ${OS}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
[[ "${DRY_RUN}" == "true" ]] && _box_line "  Mode     : DRY RUN — nothing will be removed"
[[ "${REMOVE_ALL}" == "true" ]] && _box_line "  Mode     : --all (remove all without prompting)"
_box_bot
echo ""

# ---------------------------------------------------------------------------
# Discover installed tools across all possible prefixes
# ---------------------------------------------------------------------------
declare -A TOOL_DIRS=()

for candidate_prefix in \
    "$(_get_sys_prefix)" \
    "$(_get_user_prefix)" \
    ${PREFIX_OVERRIDE:+"${PREFIX_OVERRIDE}"}; do
    if [[ -d "${candidate_prefix}" ]]; then
        while IFS= read -r entry; do
            [[ -z "${entry}" ]] && continue
            local_tool="${entry%%:*}"
            local_dir="${entry#*:}"
            TOOL_DIRS["${local_tool}:${local_dir}"]="${candidate_prefix}"
        done < <(_find_tools "${candidate_prefix}")
    fi
done

if [[ ${#TOOL_DIRS[@]} -eq 0 ]]; then
    echo "  No installed tools found."
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Show discovered tools
# ---------------------------------------------------------------------------
echo "  Installed tools found:"
echo ""
declare -a TOOL_KEYS=()
for key in "${!TOOL_DIRS[@]}"; do
    tool="${key%%:*}"
    dir="${key#*:}"
    printf "    %-30s %s\n" "${tool}" "${dir}"
    TOOL_KEYS+=("${key}")
done
echo ""

# ---------------------------------------------------------------------------
# Select tools to remove
# ---------------------------------------------------------------------------
TOOLS_TO_REMOVE=()

if [[ "${REMOVE_ALL}" == "true" ]]; then
    TOOLS_TO_REMOVE=("${TOOL_KEYS[@]}")
else
    echo "  Select tools to remove (press Enter to skip, 'y' to remove):"
    echo ""
    for key in "${TOOL_KEYS[@]}"; do
        tool="${key%%:*}"
        dir="${key#*:}"
        printf "  Remove %-30s [y/N]: " "${tool}"
        read -r reply
        [[ "${reply^^}" == "Y" ]] && TOOLS_TO_REMOVE+=("${key}")
    done
    echo ""
fi

if [[ ${#TOOLS_TO_REMOVE[@]} -eq 0 ]]; then
    echo "  Nothing selected for removal."
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Confirm
# ---------------------------------------------------------------------------
echo ""
_box_top
_box_line "  About to remove:"
_box_mid
for key in "${TOOLS_TO_REMOVE[@]}"; do
    tool="${key%%:*}"
    dir="${key#*:}"
    _box_line "  [!!]  ${tool}  ->  ${dir}"
done
_box_bot
echo ""

if [[ "${REMOVE_ALL}" == "false" && "${DRY_RUN}" == "false" ]]; then
    printf "  Confirm removal? [y/N]: "
    read -r confirm
    if [[ "${confirm^^}" != "Y" ]]; then
        echo "  Cancelled."
        echo ""
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Remove selected tools
# ---------------------------------------------------------------------------
REMOVED=()
FAILED=()

for key in "${TOOLS_TO_REMOVE[@]}"; do
    tool="${key%%:*}"
    dir="${key#*:}"
    if _remove_tool "${tool}" "${dir}"; then
        REMOVED+=("${tool}")
    else
        FAILED+=("${tool}")
    fi
done

# ---------------------------------------------------------------------------
# Clean up env.sh entries for removed tools
# ---------------------------------------------------------------------------
echo ""
echo "  Cleaning up PATH registrations..."

for candidate_prefix in "$(_get_sys_prefix)" "$(_get_user_prefix)" ${PREFIX_OVERRIDE:+"${PREFIX_OVERRIDE}"}; do
    env_file="${candidate_prefix}/env.sh"
    if [[ ! -f "${env_file}" ]]; then
        continue
    fi

    for key in "${TOOLS_TO_REMOVE[@]}"; do
        tool="${key%%:*}"
        dir="${key#*:}"
        bin_dir="${dir}/bin"

        if grep -qF "${bin_dir}" "${env_file}" 2>/dev/null; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                echo "  [dry-run] Would remove PATH entry: ${bin_dir} from ${env_file}"
            else
                grep -v "${bin_dir}" "${env_file}" > "${env_file}.tmp" \
                    && [[ -s "${env_file}.tmp" || $(wc -l < "${env_file}") -le 1 ]] \
                    && mv "${env_file}.tmp" "${env_file}" \
                    || { rm -f "${env_file}.tmp"; echo "  [WARN] Skipped env.sh rewrite — output was unexpectedly empty." >&2; }
                echo "  [OK]  Removed PATH entry: ${bin_dir}"
            fi
        fi
    done

    # If env.sh is now empty (only comments), remove it too
    if [[ -f "${env_file}" ]]; then
        non_comment="$(grep -v '^#' "${env_file}" | grep -v '^$' || true)"
        if [[ -z "${non_comment}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                echo "  [dry-run] Would remove empty env.sh: ${env_file}"
            else
                rm -f "${env_file}"
                echo "  [OK]  Removed empty env.sh: ${env_file}"
            fi
        fi
    fi
done

# ---------------------------------------------------------------------------
# Clean up ~/.bashrc if env.sh is gone
# ---------------------------------------------------------------------------
BASHRC="${HOME}/.bashrc"
for candidate_prefix in "$(_get_sys_prefix)" "$(_get_user_prefix)" ${PREFIX_OVERRIDE:+"${PREFIX_OVERRIDE}"}; do
    env_file="${candidate_prefix}/env.sh"
    if [[ ! -f "${env_file}" ]] && grep -qF "${env_file}" "${BASHRC}" 2>/dev/null; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            echo "  [dry-run] Would remove from ~/.bashrc: source \"${env_file}\""
        else
            grep -v "${env_file}" "${BASHRC}" > "${BASHRC}.tmp" \
                && [[ -s "${BASHRC}.tmp" ]] \
                && mv "${BASHRC}.tmp" "${BASHRC}" \
                || { rm -f "${BASHRC}.tmp"; echo "  [WARN] Skipped ~/.bashrc rewrite — output was unexpectedly empty." >&2; }
            echo "  [OK]  Removed env.sh source line from ~/.bashrc"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
_box_top
_box_line "  airgap-cpp-devkit — Uninstall Complete"
_box_mid
_box_line "  Platform : ${OS}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
_box_mid

if [[ ${#REMOVED[@]} -gt 0 ]]; then
    _box_line "  Removed:"
    for t in "${REMOVED[@]}"; do
        _box_line "    [OK]  ${t}"
    done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    _box_line "  FAILED:"
    for t in "${FAILED[@]}"; do
        _box_line "    [!!]  ${t}"
    done
fi

_box_bot
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  Dry run complete — nothing was removed."
else
    echo "  Restart your shell to apply PATH changes."
fi
echo ""