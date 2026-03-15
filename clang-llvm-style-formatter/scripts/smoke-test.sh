#!/usr/bin/env bash
# =============================================================================
# smoke-test.sh — Verify the clang-llvm-style-formatter submodule is working.
#
# Tests:
#   1. clang-format binary exists and reports correct version
#   2. .clang-format config exists (repo root or config/)
#   3. Pre-commit hook is installed in the host repo
#   4. Formatter correctly REJECTS badly formatted C++ code
#   5. Formatter correctly ACCEPTS properly formatted C++ code
#   6. clang-format --style=file auto-formats a file in place correctly
#
# Usage:
#   bash clang-llvm-style-formatter/scripts/smoke-test.sh
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(git -C "${SUBMODULE_ROOT}" rev-parse --show-toplevel 2>/dev/null)"

PASS=0
FAIL=0
SKIP=0

_pass() { printf "  [PASS]  %s\n" "$1"; PASS=$(( PASS + 1 )); }
_fail() { printf "  [FAIL]  %s\n" "$1" >&2; FAIL=$(( FAIL + 1 )); }
_skip() { printf "  [SKIP]  %s\n" "$1"; SKIP=$(( SKIP + 1 )); }
_section() { printf "\n── %s\n" "$1"; }

echo "=================================================================="
echo "  smoke-test.sh  —  clang-llvm-style-formatter"
echo "  Repo : ${REPO_ROOT}"
echo "  Date : $(date)"
echo "=================================================================="

# ---------------------------------------------------------------------------
# Locate clang-format binary
# ---------------------------------------------------------------------------
CF_BIN=""
for candidate in \
    "${SUBMODULE_ROOT}/bin/windows/clang-format.exe" \
    "${SUBMODULE_ROOT}/bin/linux/clang-format"; do
    [[ -x "${candidate}" ]] && { CF_BIN="${candidate}"; break; }
done
[[ -z "${CF_BIN}" ]] && command -v clang-format &>/dev/null \
    && CF_BIN="$(command -v clang-format)"

# Locate .clang-format config — prefer repo root (installed by bootstrap),
# fall back to submodule config/
CF_CONFIG=""
for loc in \
    "${REPO_ROOT}/.clang-format" \
    "${SUBMODULE_ROOT}/config/.clang-format"; do
    [[ -f "${loc}" ]] && { CF_CONFIG="${loc}"; break; }
done

# ---------------------------------------------------------------------------
# Test 1 — clang-format binary exists and runs
# ---------------------------------------------------------------------------
_section "Test 1: clang-format binary"
if [[ -n "${CF_BIN}" && -x "${CF_BIN}" ]]; then
    CF_VER="$("${CF_BIN}" --version 2>/dev/null | head -1)"
    _pass "Found: ${CF_BIN}"
    _pass "Version: ${CF_VER}"
else
    _fail "clang-format not found in bin/ or PATH"
    _fail "Run: bash ${SUBMODULE_ROOT}/bootstrap.sh"
fi

# ---------------------------------------------------------------------------
# Test 2 — .clang-format config exists
# ---------------------------------------------------------------------------
_section "Test 2: .clang-format config"
if [[ -n "${CF_CONFIG}" ]]; then
    _pass "Config: ${CF_CONFIG}"
else
    _fail ".clang-format not found in repo root or submodule config/"
fi

# ---------------------------------------------------------------------------
# Test 3 — Pre-commit hook installed
# ---------------------------------------------------------------------------
_section "Test 3: pre-commit hook"
HOOK="${REPO_ROOT}/.git/hooks/pre-commit"
if [[ -f "${HOOK}" ]]; then
    _pass "Hook installed: ${HOOK}"
    if grep -q "clang-llvm-style-formatter\|clang-format" "${HOOK}" 2>/dev/null; then
        _pass "Hook references clang-format"
    else
        _fail "Hook exists but does not reference clang-format"
    fi
else
    _fail "Pre-commit hook not installed at ${HOOK}"
    _fail "Run: bash ${SUBMODULE_ROOT}/bootstrap.sh"
fi

# ---------------------------------------------------------------------------
# Tests 4-6 require both the binary and config
# ---------------------------------------------------------------------------
if [[ -z "${CF_BIN}" || -z "${CF_CONFIG}" ]]; then
    _section "Tests 4-6: formatting checks"
    _skip "clang-format binary or config not available — skipping formatting tests"
else
    # clang-format on Windows requires a Windows-style path for --style=file:
    # Convert /c/Users/... to C:\Users\... if running on Windows
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            CF_CONFIG_NATIVE="$(cygpath -w "${CF_CONFIG}" 2>/dev/null ||                 printf '%s' "${CF_CONFIG}" | sed 's|/c/|C:\|; s|/|\|g')"
            ;;
        *)
            CF_CONFIG_NATIVE="${CF_CONFIG}"
            ;;
    esac
    STYLE_ARG="--style=file:${CF_CONFIG_NATIVE}"

    # -------------------------------------------------------------------------
    # Test 4 — Badly formatted code is rejected
    # -------------------------------------------------------------------------
    _section "Test 4: reject bad formatting"
    TMPDIR_TEST="$(mktemp -d)"
    BAD_FILE="${TMPDIR_TEST}/bad.cpp"
    cat > "${BAD_FILE}" << 'CPP'
int main(){int x=1;if(x>0){return x;}return 0;}
CPP
    if "${CF_BIN}" "${STYLE_ARG}" --dry-run --Werror "${BAD_FILE}" &>/dev/null; then
        _fail "Badly formatted code was NOT flagged (formatter may be misconfigured)"
    else
        _pass "Badly formatted code correctly flagged as needing reformatting"
    fi
    rm -rf "${TMPDIR_TEST}"

    # -------------------------------------------------------------------------
    # Test 5 — Well-formatted code is accepted
    # -------------------------------------------------------------------------
    _section "Test 5: accept good formatting"
    TMPDIR_TEST="$(mktemp -d)"
    GOOD_FILE="${TMPDIR_TEST}/good.cpp"
    # LLVM style: 2-space indent, braces on same line, spaces around operators
    cat > "${GOOD_FILE}" << 'CPP'
int main() {
  int x = 1;
  if (x > 0) {
    return x;
  }
  return 0;
}
CPP
    if "${CF_BIN}" "${STYLE_ARG}" --dry-run --Werror "${GOOD_FILE}" &>/dev/null; then
        _pass "Well-formatted code accepted with no changes"
    else
        _fail "Well-formatted code incorrectly flagged — check .clang-format config"
        EXPECTED="$("${CF_BIN}" "${STYLE_ARG}" "${GOOD_FILE}" 2>/dev/null)"
        echo "  clang-format wants:" >&2
        echo "${EXPECTED}" | head -10 | sed 's/^/    /' >&2
    fi
    rm -rf "${TMPDIR_TEST}"

    # -------------------------------------------------------------------------
    # Test 6 — In-place formatting works correctly
    # -------------------------------------------------------------------------
    _section "Test 6: in-place formatting"
    TMPDIR_TEST="$(mktemp -d)"
    FIX_FILE="${TMPDIR_TEST}/fix_me.cpp"
    cat > "${FIX_FILE}" << 'CPP'
int main(){int x=1;return x;}
CPP
    # Format in place using -i flag directly (not fix-format.sh which works on staged files)
    "${CF_BIN}" "${STYLE_ARG}" -i "${FIX_FILE}" 2>/dev/null

    if "${CF_BIN}" "${STYLE_ARG}" --dry-run --Werror "${FIX_FILE}" &>/dev/null; then
        _pass "In-place formatting produced correctly formatted output"
        echo "  Formatted result:"
        sed 's/^/    /' "${FIX_FILE}"
    else
        _fail "In-place formatting did not produce correct output"
        echo "  Result:" >&2
        cat "${FIX_FILE}" | sed 's/^/    /' >&2
    fi
    rm -rf "${TMPDIR_TEST}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=================================================================="
TOTAL=$(( PASS + FAIL + SKIP ))
printf "  Results: %d passed  |  %d failed  |  %d skipped  |  %d total\n" \
    "${PASS}" "${FAIL}" "${SKIP}" "${TOTAL}"
echo "=================================================================="
echo ""

if [[ ${FAIL} -eq 0 ]]; then
    echo "  All tests passed. The formatter is working correctly."
    echo ""
    exit 0
else
    echo "  ${FAIL} test(s) failed. See output above for details." >&2
    echo ""
    exit 1
fi