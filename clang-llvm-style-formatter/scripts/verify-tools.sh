#!/usr/bin/env bash
# =============================================================================
# verify-tools.sh — Verify clang-format (and optionally clang-tidy) are
#                   present, on PATH, and meet the minimum version requirement.
#
# On success  : exits 0, prints a summary.
# On failure  : exits 1 with a platform-specific message explaining how
#               to build clang-format from the vendored source in llvm-src/.
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
# OS detection
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
# Tool discovery — tries PATH first, then all known install locations.
# Mirrors find-tools.sh so both scripts agree on where to look.
# ---------------------------------------------------------------------------
_find_tool() {
    local tool="$1"

    # 1. Plain name on PATH
    if command -v "${tool}" &>/dev/null; then
        command -v "${tool}"
        return 0
    fi

    # 2. Versioned suffixes on PATH
    for ver in 18 17 16 15 14 13 12; do
        if command -v "${tool}-${ver}" &>/dev/null; then
            command -v "${tool}-${ver}"
            return 0
        fi
    done

    # 3a. pip venv (preferred)
    for _bundled in         "${SUBMODULE_ROOT}/.venv/Scripts/${tool}.exe"         "${SUBMODULE_ROOT}/.venv/bin/${tool}"; do
        [[ -x "${_bundled}" ]] && { echo "${_bundled}"; return 0; }
    done
    # 3b. clang-llvm-source-build bin/ (optional LLVM source build)
    for _bundled in         "${SUBMODULE_ROOT}/../clang-llvm-source-build/bin/windows/${tool}.exe"         "${SUBMODULE_ROOT}/../clang-llvm-source-build/bin/linux/${tool}"; do
        [[ -x "${_bundled}" ]] && { echo "${_bundled}"; return 0; }
    done

    # 3. Windows heuristic paths
    if [[ "${OS}" == "windows" ]]; then
        for vs_year in 2022 2019 2017; do
            for edition in Enterprise Professional Community; do
                for p in \
                    "/c/Program Files/Microsoft Visual Studio/${vs_year}/${edition}/VC/Tools/Llvm/x64/bin/${tool}.exe" \
                    "/c/Program Files/Microsoft Visual Studio/${vs_year}/${edition}/VC/Tools/Llvm/bin/${tool}.exe" \
                    "/c/Program Files (x86)/Microsoft Visual Studio/${vs_year}/${edition}/VC/Tools/Llvm/bin/${tool}.exe"; do
                    [[ -x "${p}" ]] && { echo "${p}"; return 0; }
                done
            done
            for p in \
                "/c/Program Files (x86)/Microsoft Visual Studio/${vs_year}/BuildTools/VC/Tools/Llvm/x64/bin/${tool}.exe" \
                "/c/Program Files (x86)/Microsoft Visual Studio/${vs_year}/BuildTools/VC/Tools/Llvm/bin/${tool}.exe"; do
                [[ -x "${p}" ]] && { echo "${p}"; return 0; }
            done
        done
        for p in \
            "/c/Program Files/LLVM/bin/${tool}.exe" \
            "/c/Program Files (x86)/LLVM/bin/${tool}.exe"; do
            [[ -x "${p}" ]] && { echo "${p}"; return 0; }
        done
    fi

    # 4. RHEL 8 / Linux heuristic paths
    if [[ "${OS}" == "rhel" || "${OS}" == "linux" ]]; then
        for ver in 18 17 16 15 14 13; do
            for p in \
                "/usr/bin/${tool}-${ver}" \
                "/usr/lib/llvm-${ver}/bin/${tool}" \
                "/opt/rh/llvm-toolset-${ver}/root/usr/bin/${tool}" \
                "/opt/rh/llvm-toolset/root/usr/bin/${tool}"; do
                [[ -x "${p}" ]] && { echo "${p}"; return 0; }
            done
        done
        for p in \
            "/usr/bin/${tool}" \
            "/usr/local/bin/${tool}" \
            "${HOME}/llvm-local/bin/${tool}" \
            "/opt/llvm/bin/${tool}"; do
            [[ -x "${p}" ]] && { echo "${p}"; return 0; }
        done
    fi

    return 1
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
# Platform-specific build guidance — shown when clang-format is missing/old.
# Directs the developer to build from the vendored source in llvm-src/.
# ---------------------------------------------------------------------------
_print_build_guidance_windows() {
    local tool="$1"
    local issue="$2"
    echo "" >&2
    echo "  ┌─────────────────────────────────────────────────────────────┐" >&2
    echo "  │         Build clang-format from vendored source             │" >&2
    echo "  └─────────────────────────────────────────────────────────────┘" >&2
    echo "" >&2
    if [[ "${issue}" != "missing" ]]; then
        local found_ver="${issue#outdated:}"
        echo "  Version ${found_ver} was found but >= ${MIN_VERSION} is required." >&2
        echo "" >&2
    fi
    echo "  The LLVM source is already in this submodule." >&2
    echo "  Build clang-format locally — no network access required." >&2
    echo "" >&2
    echo "  Prerequisites (must already be on this machine):" >&2
    echo "    • Visual Studio 2017/2019/2022 with C++ workload" >&2
    echo "    • CMake 3.14+  (bundled with VS 2019+)" >&2
    echo "    • Ninja        (bundled with VS)" >&2
    echo "" >&2
    echo "  Run from an x64 Native Tools Command Prompt for VS:" >&2
    echo "    bash ${SUBMODULE_ROOT}/../clang-llvm-source-build/bootstrap.sh" >&2
    echo "" >&2
    echo "  Build time: ~30–45 min. Disk required: ~5 GB during build." >&2
    echo "  Binary output: ${SUBMODULE_ROOT}/bin/windows/clang-format.exe" >&2
    echo "" >&2
    echo "  Full prerequisites: ${DOCS_DIR}/llvm-install-guide.md" >&2
    echo "" >&2
}

_print_build_guidance_rhel() {
    local tool="$1"
    local issue="$2"
    echo "" >&2
    echo "  ┌─────────────────────────────────────────────────────────────┐" >&2
    echo "  │         Build clang-format from vendored source             │" >&2
    echo "  └─────────────────────────────────────────────────────────────┘" >&2
    echo "" >&2
    if [[ "${issue}" != "missing" ]]; then
        local found_ver="${issue#outdated:}"
        echo "  Version ${found_ver} was found but >= ${MIN_VERSION} is required." >&2
        echo "" >&2
    fi
    echo "  The LLVM source is already included in this submodule." >&2
    echo "  Build clang-format locally — no network access required." >&2
    echo "" >&2
    echo "  Prerequisites (must already be installed):" >&2
    echo "    • GCC/G++ 8+      (gcc-c++ package)" >&2
    echo "    • CMake 3.14+     (cmake package)" >&2
    echo "    • Ninja           (ninja-build package, recommended)" >&2
    echo "" >&2
    echo "  Check prerequisites:" >&2
    echo "    gcc --version && cmake --version && ninja --version" >&2
    echo "" >&2
    echo "  Then build:" >&2
    echo "    bash ${SUBMODULE_ROOT}/../clang-llvm-source-build/bootstrap.sh" >&2
    echo "" >&2
    echo "  Build time: ~45–60 minutes. Disk needed: ~5 GB during build." >&2
    echo "  After building, the binary lives at:" >&2
    echo "    ${SUBMODULE_ROOT}/bin/linux/clang-format" >&2
    echo "" >&2
    echo "  See build prerequisites: ${DOCS_DIR}/llvm-install-guide.md" >&2
    echo "" >&2
}

_print_build_guidance() {
    local tool="$1" issue="$2"
    case "${OS}" in
        windows) _print_build_guidance_windows "${tool}" "${issue}" ;;
        rhel)    _print_build_guidance_rhel    "${tool}" "${issue}" ;;
        *)
            echo "" >&2
            echo "  Build ${tool} from vendored source (~30-60 min):" >&2
            echo "    bash ${SUBMODULE_ROOT}/../clang-llvm-source-build/bootstrap.sh" >&2
            echo "  Or install via pip/venv (~5 sec):" >&2
            echo "    bash ${SUBMODULE_ROOT}/bootstrap.sh" >&2
            echo "  See: ${DOCS_DIR}/llvm-install-guide.md" >&2
            echo "" >&2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Version too old — different message: IT needs to UPDATE, not install
# ---------------------------------------------------------------------------
_print_version_upgrade_brief() {
    local tool="$1" found_path="$2" found_ver="$3"
    _print_build_guidance "${tool}" "outdated:${found_ver}"
}

# ---------------------------------------------------------------------------
# Single-tool verification
# ---------------------------------------------------------------------------
OVERALL_PASS=true

_verify_tool() {
    local tool="$1"
    local required="$2"   # "required" or "optional"

    echo "  Checking ${tool}…"

    local found_path
    found_path="$(_find_tool "${tool}" 2>/dev/null || true)"

    if [[ -z "${found_path}" ]]; then
        if [[ "${required}" == "required" ]]; then
            _fail "${tool} — NOT FOUND"
            OVERALL_PASS=false
            # Check if vendored source is available to build from
            if [[ -d "${SUBMODULE_ROOT}/../clang-llvm-source-build/llvm-src" ]]; then
                echo "" >&2
                echo "  Vendored LLVM source is present in clang-llvm-source-build/." >&2
                echo "  Build clang-format from source (~30-60 min):" >&2
                echo "    bash ${SUBMODULE_ROOT}/../clang-llvm-source-build/bootstrap.sh" >&2
                echo "" >&2
                echo "  Or install via pip/venv (~5 sec):" >&2
                echo "    bash ${SUBMODULE_ROOT}/bootstrap.sh" >&2
                echo "" >&2
            else
                _print_build_guidance "${tool}" "missing"
            fi
        else
            _warn "${tool} — not found (optional — skipping)"
        fi
        return
    fi

    # Found — check version
    local ver
    ver="$(_major_version "${found_path}" 2>/dev/null || echo "0")"

    if [[ -z "${ver}" || "${ver}" -lt "${MIN_VERSION}" ]]; then
        _fail "${tool} — version ${ver:-unknown} is below minimum ${MIN_VERSION}"
        OVERALL_PASS=false
        _print_version_upgrade_brief "${tool}" "${found_path}" "${ver:-unknown}"
        return
    fi

    _ok "${tool} ${ver}.x — ${found_path}"

    # Warn if not on PATH (hook will still work via find-tools.sh, but worth noting)
    if ! command -v "${tool}" &>/dev/null; then
        _warn "${tool} found at ${found_path} but is NOT on your PATH."
        _info "Run: bash ${SUBMODULE_ROOT}/scripts/setup-user-path.sh --auto"
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
    echo "  This machine requires IT intervention to proceed." >&2
    echo "  The pre-commit hook will not function until this is resolved." >&2
    echo "" >&2
    exit 1
fi