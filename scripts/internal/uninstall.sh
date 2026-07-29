#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# uninstall.sh
#
# Removes installed airgap-cpp-devkit tools and cleans up PATH registration.
#
# USAGE:
#   bash scripts/internal/uninstall.sh              # interactive — choose which tools to remove
#   bash scripts/internal/uninstall.sh --all        # remove everything without prompting
#   bash scripts/internal/uninstall.sh --prefix <path>   # look for installs under custom prefix
#
# OPTIONS:
#   --all              Remove all installed tools without prompting
#   --prefix <path>    Override install prefix to search
#   --dry-run          Show what would be removed without removing anything
# =============================================================================

set -euo pipefail

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
# Find installed tools under a prefix (receipt-driven — see _find_tools)
# ---------------------------------------------------------------------------
_find_tools() {
    local base="$1"
    local found=() dir
    # Receipt-driven discovery: any child dir of the prefix that carries an
    # INSTALL_RECEIPT.txt was installed by the devkit. This can't drift from the
    # installer the way the old hand-maintained ALL_TOOL_PATHS table did — that
    # table silently missed conan/sqlite/zlib and used a stale path for the style
    # formatter, so a "full" uninstall left them (and hence env.sh + the ~/.bashrc
    # line) behind. Covers the flat <prefix>/<tool> layout and the versioned
    # grpc-<ver>-* / clang-style-formatter / vscode-extensions dirs alike.
    shopt -s nullglob
    for dir in "${base}"/*/; do
        dir="${dir%/}"
        [[ -f "${dir}/INSTALL_RECEIPT.txt" ]] && found+=("$(basename "${dir}"):${dir}")
    done
    shopt -u nullglob
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
# Clean up env.sh + the ~/.bashrc source line
#
# env.sh is a single per-prefix file that globs "<prefix>/*/bin" (and
# "<prefix>/*/*/bin") onto PATH — it holds NO per-tool lines to strip, so it
# self-adjusts as tool dirs disappear. The old logic tried to grep each tool's
# bin_dir out of env.sh and then treated the glob loop as leftover content, so
# env.sh was never emptied and its ~/.bashrc source line was never removed —
# leaving both orphaned after a full uninstall. The correct signal is simply
# whether any INSTALL_RECEIPT remains under the prefix (what _find_tools keys
# off): none left → remove env.sh and its ~/.bashrc line; some left → keep both.
# ---------------------------------------------------------------------------
echo ""
echo "  Cleaning up PATH registrations..."

BASHRC="${HOME}/.bashrc"

# Dirs slated for removal. Under --dry-run these are still on disk, so "do tools
# remain?" must be judged against the POST-removal state (discovered receipts
# minus this set), not a fresh disk scan — otherwise a dry-run --all would wrongly
# report "keeping env.sh" for a prefix it would in fact empty.
declare -A _REMOVING=()
for key in "${TOOLS_TO_REMOVE[@]}"; do _REMOVING["${key#*:}"]=1; done

for candidate_prefix in "$(_get_sys_prefix)" "$(_get_user_prefix)" ${PREFIX_OVERRIDE:+"${PREFIX_OVERRIDE}"}; do
    env_file="${candidate_prefix}/env.sh"
    [[ -f "${env_file}" ]] || continue

    # Any receipt-bearing tool dir under this prefix that is NOT being removed?
    # If so, env.sh is still needed and stays.
    remaining=""
    while IFS= read -r _entry; do
        [[ -z "${_entry}" ]] && continue
        [[ -n "${_REMOVING["${_entry#*:}"]:-}" ]] && continue
        remaining=1; break
    done < <(_find_tools "${candidate_prefix}")
    if [[ -n "${remaining}" ]]; then
        echo "  [--]  Tools remain under ${candidate_prefix} — keeping env.sh."
        continue
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [dry-run] Would remove env.sh: ${env_file}"
        grep -qF "${env_file}" "${BASHRC}" 2>/dev/null \
            && echo "  [dry-run] Would remove its source line from ${BASHRC}"
        continue
    fi

    rm -f "${env_file}"
    echo "  [OK]  Removed env.sh: ${env_file}"

    # Drop the guarded source line and its comment header from ~/.bashrc. grep -v
    # exits 1 when it filters out every line (a ~/.bashrc that held only the devkit
    # lines) — a legitimate empty result, not an error — so accept rc<=1 and bail
    # only on a real grep error (rc>=2). `|| _grc=$?` keeps set -e from aborting.
    if grep -qF "${env_file}" "${BASHRC}" 2>/dev/null; then
        _grc=0
        grep -v -e "${env_file}" \
                -e '^# airgap-cpp-devkit -- added by install\.sh$' \
                "${BASHRC}" > "${BASHRC}.tmp" || _grc=$?
        if [[ ${_grc} -le 1 ]]; then
            mv "${BASHRC}.tmp" "${BASHRC}"
            echo "  [OK]  Removed env.sh source line from ${BASHRC}"
        else
            rm -f "${BASHRC}.tmp"
            echo "  [WARN] Skipped ${BASHRC} rewrite — grep error (rc=${_grc})." >&2
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