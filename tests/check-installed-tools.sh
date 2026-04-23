#!/usr/bin/env bash
# tests/check-installed-tools.sh
#
# For every tool that has an INSTALL_RECEIPT.txt, runs the check_cmd
# defined in its devkit.json and reports pass/fail.
#
# Usage: bash tests/check-installed-tools.sh [--verbose] [--prefix <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"

VERBOSE=false
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose) VERBOSE=true; shift ;;
        --prefix)  PREFIX_OVERRIDE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

PASS=0; FAIL=0; SKIP=0

_pass() { PASS=$((PASS+1)); printf "  PASS  %s\n" "$1"; }
_fail() { FAIL=$((FAIL+1)); printf "  FAIL  %s\n" "$1"; }
_skip() { SKIP=$((SKIP+1)); $VERBOSE && printf "  SKIP  %s\n" "$1" || true; }
_sep()  { printf "%.0s─" {1..60}; printf "\n"; }

# ── Resolve install prefix ───────────────────────────────────────────────────
_detect_prefix() {
    if [[ -n "$PREFIX_OVERRIDE" ]]; then
        echo "$PREFIX_OVERRIDE"; return
    fi
    if [[ "${OS:-}" == "Windows_NT" ]] || \
       [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || \
       [[ "$(uname -s 2>/dev/null)" == MSYS* ]]; then
        local la="${LOCALAPPDATA:-}"
        [[ -n "$la" ]] && echo "${la}/airgap-cpp-devkit" && return
        echo "C:/Users/$USER/AppData/Local/airgap-cpp-devkit"
    else
        echo "${HOME}/.local/share/airgap-cpp-devkit"
    fi
}

PREFIX="$(_detect_prefix)"

# Source the env file if present so installed tool PATHs are available
ENV_FILE="$PREFIX/env.sh"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" 2>/dev/null || true

_py() {
    if command -v python3 &>/dev/null; then python3 "$@"
    elif command -v python  &>/dev/null; then python  "$@"
    else echo "ERROR: python not found" >&2; exit 1
    fi
}

_pypath() {
    if command -v cygpath &>/dev/null 2>&1; then cygpath -m "$1"
    else echo "$1"
    fi
}

_json_get() {
    local p; p="$(_pypath "$1")"
    _py -c "
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
    v = d.get(sys.argv[2])
    if isinstance(v, bool): print(str(v).lower())
    elif v is not None:     print(str(v))
" "$p" "$2" 2>/dev/null || true
}

# ── Detect platform ──────────────────────────────────────────────────────────
_is_windows() {
    [[ "${OS:-}" == "Windows_NT" ]] || \
    [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || \
    [[ "$(uname -s 2>/dev/null)" == MSYS* ]]
}
CURRENT_OS="linux"
_is_windows && CURRENT_OS="windows"

_sep
printf " airgap-cpp-devkit — Installed Tool check_cmd Verification\n"
printf " Prefix : %s\n" "$PREFIX"
printf " OS     : %s\n" "$CURRENT_OS"
_sep

if [[ ! -d "$TOOLS_DIR" ]]; then
    printf " SKIP  tools/ submodule not initialised\n"
    exit 0
fi

while IFS= read -r -d '' devkit_json; do
    tool_id="$(_json_get "$devkit_json" id)"
    tool_name="$(_json_get "$devkit_json" name)"
    check_cmd="$(_json_get "$devkit_json" check_cmd)"
    platform="$(_json_get "$devkit_json" platform)"
    receipt_name="$(_json_get "$devkit_json" receipt_name)"

    # Skip tools not applicable to current platform
    if [[ "$platform" == "windows" && "$CURRENT_OS" != "windows" ]]; then
        _skip "$tool_name — Windows-only"; continue
    fi
    if [[ "$platform" == "linux" && "$CURRENT_OS" != "linux" ]]; then
        _skip "$tool_name — Linux-only"; continue
    fi

    # Only test tools that are actually installed (have a receipt)
    receipt="${PREFIX}/${receipt_name}/INSTALL_RECEIPT.txt"
    if [[ ! -f "$receipt" ]]; then
        _skip "$tool_name — not installed (no receipt at $receipt)"
        continue
    fi

    if [[ -z "$check_cmd" ]]; then
        _skip "$tool_name — no check_cmd defined"
        continue
    fi

    # Run the check_cmd through bash so shell metacharacters (pipes, redirects)
    # work as intended. check_cmd values come exclusively from tools/ devkit.json
    # files (the trusted submodule) — user-packages/ is not searched by this script.
    if output=$(bash -c "$check_cmd" 2>&1); then
        first_line="$(echo "$output" | head -1)"
        _pass "$tool_name — $first_line"
    else
        _fail "$tool_name — check_cmd failed: $check_cmd"
        $VERBOSE && echo "    Output: $output"
    fi
done < <(find "$TOOLS_DIR" -name "devkit.json" -print0)

_sep
printf "  PASS %-4d   FAIL %-4d   SKIP %-4d\n" "$PASS" "$FAIL" "$SKIP"
_sep
printf "\n"

[[ $FAIL -eq 0 ]]
