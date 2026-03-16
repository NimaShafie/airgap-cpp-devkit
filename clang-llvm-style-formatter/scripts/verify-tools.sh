#!/usr/bin/env bash
# =============================================================================
# verify-tools.sh — Verify clang-format (and optionally clang-tidy) are
#                   present, on PATH, and meet the minimum version requirement.
#
# On success  : exits 0, prints a summary.
# On failure  : exits 1 with a platform-specific message explaining how
#               to install clang-format.
#
# Usage:
#   bash scripts/verify-tools.sh [--tidy] [--min-version <N>] [--quiet]
#
# Options:
#   --tidy           Also verify clang-tidy (off by default).
#   --min-version N  Minimum accepted major version (default: 14).
#   --quiet          Suppress banner; only print actionable lines.
#                    Used internally by bootstrap.sh.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CHECK_TIDY=false
MIN_VERSION=14
QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tidy)        CHECK_TIDY=true;  shift ;;
        --min-version) MIN_VERSION="$2"; shift 2 ;;
        --quiet)       QUIET=true;       shift ;;
        -h|--help)
            echo "Usage: $0 [--tidy] [--min-version <N>] [--quiet]"
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCS_DIR="${SUBMODULE_ROOT}/docs"

# ---------------------------------------------------------------------------
# Load config (default then local override) and run shared tool discovery.
# This is the single source of truth — no duplicated _find_tool logic here.
# ---------------------------------------------------------------------------
CONF="${SUBMODULE_ROOT}/config/hooks.conf"
CONF_LOCAL="${SUBMODULE_ROOT}/.llvm-hooks-local/hooks.conf"
# shellcheck source=/dev/null
source "${CONF}"
# shellcheck source=/dev/null
[[ -f "${CONF_LOCAL}" ]] && source "${CONF_LOCAL}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/find-tools.sh"

# ---------------------------------------------------------------------------
# OS detection (used for guidance messages only)
# ---------------------------------------------------------------------------
_detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)
            if [[ -f /etc/redhat-release ]]; then echo "rhel"
            else echo "linux"; fi ;;
        Darwin*) echo "macos" ;;
        *)        echo "unknown" ;;
    esac
}
OS="$(_detect_os)"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
_banner() {
    [[ "${QUIET}" == "true" ]] && return
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║         clang-llvm-style-formatter — Tool Verification          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo "  Platform : ${OS}"
    echo "  Min ver  : clang-format >= ${MIN_VERSION}.x"
    echo ""
}

_ok()   { echo "  ✓  $*"; }
_fail() { echo "  ✗  $*" >&2; }
_info() { [[ "${QUIET}" == "false" ]] && echo "     $*"; }
_warn() { echo "  ⚠  $*" >&2; }

# ---------------------------------------------------------------------------
# Platform-specific guidance — shown when clang-format is missing or old
# ---------------------------------------------------------------------------
_print_build_guidance_windows() {
    local issue="$1"
    echo "" >&2
    echo "  ┌─────────────────────────────────────────────────────────────┐" >&2
    echo "  │         Install or build clang-format                       │" >&2
    echo "  └─────────────────────────────────────────────────────────────┘" >&2
    echo "" >&2
    if [[ "${issue}" != "missing" ]]; then
        local found_ver="${issue#outdated:}"
        echo "  Version ${found_ver} was found but >= ${MIN_VERSION} is required." >&2
        echo "" >&2
    fi
    echo "  Fast path — install from vendored Python wheel (~5 seconds):" >&2
    echo "    bash ${SUBMODULE_ROOT}/bootstrap.sh" >&2
    echo "" >&2
    echo "  Slow path — build from LLVM source (~30-45 min):" >&2
    echo "    Prerequisites: Visual Studio 2017/2019/2022 (C++ workload), CMake 3.14+" >&2
    echo "    bash ${SUBMODULE_ROOT}/../clang-llvm-source-build/bootstrap.sh" >&2
    echo "" >&2
    echo "  Full prerequisites: ${DOCS_DIR}/llvm-install-guide.md" >&2
    echo "" >&2
}

_print_build_guidance_rhel() {
    local issue="$1"
    echo "" >&2
    echo "  ┌─────────────────────────────────────────────────────────────┐" >&2
    echo "  │         Install or build clang-format                       │" >&2
    echo "  └─────────────────────────────────────────────────────────────┘" >&2
    echo "" >&2
    if [[ "${issue}" != "missing" ]]; then
        local found_ver="${issue#outdated:}"
        echo "  Version ${found_ver} was found but >= ${MIN_VERSION} is required." >&2
        echo "" >&2
    fi
    echo "  Fast path — install from vendored Python wheel (~5 seconds):" >&2
    echo "    bash ${SUBMODULE_ROOT}/bootstrap.sh" >&2
    echo "" >&2
    echo "  Slow path — build from LLVM source (~45-60 min):" >&2
    echo "    Prerequisites: GCC/G++ 8+, CMake 3.14+, Ninja" >&2
    echo "    bash ${SUBMODULE_ROOT}/../clang-llvm-source-build/bootstrap.sh" >&2
    echo "" >&2
    echo "  See: ${DOCS_DIR}/llvm-install-guide.md" >&2
    echo "" >&2
}

_print_build_guidance() {
    local issue="$1"
    case "${OS}" in
        windows) _print_build_guidance_windows "${issue}" ;;
        rhel)    _print_build_guidance_rhel    "${issue}" ;;
        *)
            echo "" >&2
            echo "  Fast path (~5 sec):   bash ${SUBMODULE_ROOT}/bootstrap.sh" >&2
            echo "  Slow path (~30-60 min): bash ${SUBMODULE_ROOT}/../clang-llvm-source-build/bootstrap.sh" >&2
            echo "  See: ${DOCS_DIR}/llvm-install-guide.md" >&2
            echo "" >&2
            ;;
    esac
}

# Extract major version number from "clang-format version X.Y.Z (...)"
_major_version() {
    local bin="$1"
    "${bin}" --version 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1 \
        | cut -d. -f1
}

# ---------------------------------------------------------------------------
# Single-tool verification
# Uses CLANG_FORMAT_BIN / CLANG_TIDY_BIN already resolved by find-tools.sh
# ---------------------------------------------------------------------------
OVERALL_PASS=true

_verify_tool() {
    local tool="$1"
    local required="$2"   # "required" or "optional"

    echo "  Checking ${tool}…"

    # find-tools.sh has already resolved the best path into the BIN variable.
    # Must uppercase: clang-format → CLANG_FORMAT_BIN (not clang_format_BIN).
    local bin_var
    bin_var="$(echo "${tool//-/_}_BIN" | tr '[:lower:]' '[:upper:]')"
    local found_path="${!bin_var:-}"

    # If find-tools.sh didn't resolve it (empty or still the bare name), it's not found
    if [[ -z "${found_path}" ]] || { [[ "${found_path}" == "${tool}" ]] && ! command -v "${tool}" &>/dev/null; }; then
        if [[ "${required}" == "required" ]]; then
            _fail "${tool} — NOT FOUND"
            OVERALL_PASS=false
            _print_build_guidance "missing"
        else
            _warn "${tool} — not found (optional — skipping)"
        fi
        return
    fi

    # Resolve bare name to full path for version check
    if [[ "${found_path}" == "${tool}" ]]; then
        found_path="$(command -v "${tool}")"
    fi

    # Found — check version
    local ver
    ver="$(_major_version "${found_path}" 2>/dev/null || echo "0")"

    if [[ -z "${ver}" || "${ver}" -lt "${MIN_VERSION}" ]]; then
        _fail "${tool} — version ${ver:-unknown} is below minimum ${MIN_VERSION}"
        OVERALL_PASS=false
        _print_build_guidance "outdated:${ver:-unknown}"
        return
    fi

    _ok "${tool} ${ver}.x — ${found_path}"

    # Informational note if not on system PATH (hook still works via find-tools.sh)
    if ! command -v "${tool}" &>/dev/null; then
        _warn "${tool} found at ${found_path} but is NOT on your system PATH."
        _info "This is fine — the pre-commit hook finds it automatically."
        _info "To add it to PATH: bash ${SUBMODULE_ROOT}/scripts/setup-user-path.sh --auto"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
_banner

_verify_tool "clang-format" "required"

if [[ "${CHECK_TIDY}" == "true" ]]; then
    _verify_tool "clang-tidy" "optional"
fi

echo ""

if [[ "${OVERALL_PASS}" == "true" ]]; then
    [[ "${QUIET}" == "false" ]] && echo "  All required tools verified ✓"
    echo ""
    exit 0
else
    echo "  ── Summary ─────────────────────────────────────────────────────" >&2
    echo "  One or more required tools are missing or out of date." >&2
    echo "  The pre-commit hook will not function until this is resolved." >&2
    echo "" >&2
    exit 1
fi