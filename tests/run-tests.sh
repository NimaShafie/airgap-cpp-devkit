#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# tests/run-tests.sh
#
# Automated smoke test suite for airgap-cpp-devkit.
# Verifies that all installed tools are functional after a complete install.
#
# USAGE:
#   bash tests/run-tests.sh [--prefix <path>] [--verbose]
#
# OPTIONS:
#   --prefix <path>   Path to install prefix (default: auto-detected)
#   --verbose         Show full output for each test
#
# EXIT CODES:
#   0  -- all tests passed
#   1  -- one or more tests failed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERBOSE=false
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)  PREFIX_OVERRIDE="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Detect platform and prefix
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  Linux*)                OS="linux"   ;;
  *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  PREFIX="${PREFIX_OVERRIDE}"
elif [[ "${OS}" == "windows" ]]; then
  PREFIX="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null || echo "${HOME}/AppData/Local")/airgap-cpp-devkit"
else
  # Try system-wide first, fall back to user
  if [[ -d "/opt/airgap-cpp-devkit" ]]; then
    PREFIX="/opt/airgap-cpp-devkit"
  else
    PREFIX="${HOME}/.local/share/airgap-cpp-devkit"
  fi
fi

# Source env.sh if available
ENV_FILE="${PREFIX}/env.sh"
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
SKIP=0
NA=0

_sep() { printf '%s\n' "--------------------------------------------------------------------------------"; }
_ok()   { printf "  %-50s [OK]\n"   "$1"; (( PASS++ )) || true; }
_fail() { printf "  %-50s [FAIL]\n" "$1" >&2; (( FAIL++ )) || true; }
_skip() { printf "  %-50s [SKIP]\n" "$1"; (( SKIP++ )) || true; }
_na()   { printf "  %-50s [N/A]\n"  "$1"; (( NA++   )) || true; }

_check_bin() {
  local label="$1" cmd="$2"
  shift 2
  local args=("$@")
  if command -v "${cmd}" &>/dev/null; then
    local out
    out="$("${cmd}" "${args[@]}" 2>&1 | head -1)"
    if [[ $? -eq 0 ]]; then
      if [[ "${VERBOSE}" == "true" ]]; then
        _ok "${label}: ${out}"
      else
        _ok "${label}"
      fi
    else
      _fail "${label} (command failed)"
    fi
  else
    _fail "${label} (not found on PATH: ${cmd})"
  fi
}

_check_file() {
  local label="$1" path="$2"
  if [[ -f "${path}" || -x "${path}" ]]; then
    _ok "${label}"
  else
    _fail "${label} (not found: ${path})"
  fi
}

_receipt_exists() {
  local tool_dir="$1"
  [[ -f "${PREFIX}/${tool_dir}/INSTALL_RECEIPT.txt" ]]
}

_check_bin_receipt() {
  local label="$1" tool_dir="$2" cmd="$3"
  shift 3
  local args=("$@")
  if ! _receipt_exists "${tool_dir}"; then
    _skip "${label} (not installed)"
    return
  fi
  _check_bin "${label}" "${cmd}" "${args[@]}"
}

_check_python_import() {
  local label="$1" module="$2"
  local py_bin
  if [[ "${OS}" == "windows" ]]; then
    py_bin="${PREFIX}/python/python.exe"
  else
    py_bin="${PREFIX}/python/bin/python3"
  fi
  if ! _receipt_exists "python"; then
    _skip "${label} (python not installed)"
    return
  fi
  if [[ ! -f "${py_bin}" ]]; then
    _fail "${label} (python binary missing at ${py_bin})"
    return
  fi
  if "${py_bin}" -c "import ${module}" 2>/dev/null; then
    _ok "${label}"
  else
    _fail "${label} (import ${module} failed)"
  fi
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo "  airgap-cpp-devkit -- Smoke Tests"
echo "================================================================================"
echo ""
echo "  Platform : ${OS}  (only ${OS} tests will be run; others are marked N/A)"
echo "  Prefix   : ${PREFIX}"
echo "  Date     : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ---------------------------------------------------------------------------
# 1. Toolchains
# ---------------------------------------------------------------------------
_sep
echo "  [1] Toolchains"
_sep
_check_bin_receipt "clang-format 22.1.2" "toolchains/clang/source-build" clang-format --version
_check_bin_receipt "clang-tidy 22.1.2"   "toolchains/clang/source-build" clang-tidy   --version

# ---------------------------------------------------------------------------
# 2. Build tools
# ---------------------------------------------------------------------------
_sep
echo "  [2] Build Tools"
_sep
_check_bin_receipt "cmake" "cmake" cmake --version
if [[ "${OS}" == "linux" ]]; then
  _check_bin_receipt "lcov 2.4" "lcov" lcov    --version
  _check_bin_receipt "genhtml"  "lcov" genhtml --version
else
  _na "lcov (Linux only)"
  _na "genhtml (Linux only)"
fi

# ---------------------------------------------------------------------------
# 3. Python interpreter
# ---------------------------------------------------------------------------
_sep
echo "  [3] Python"
_sep
if [[ "${OS}" == "windows" ]]; then
  PY_BIN="${PREFIX}/python/python.exe"
else
  PY_BIN="${PREFIX}/python/bin/python3"
fi
if ! _receipt_exists "python"; then
  _skip "python (not installed)"
elif [[ -f "${PY_BIN}" ]]; then
  _ok "python binary exists"
  VER="$("${PY_BIN}" --version 2>&1)"
  _ok "python version: ${VER}"
else
  _fail "python binary missing at ${PY_BIN}"
fi

# ---------------------------------------------------------------------------
# 4. Pip packages
# ---------------------------------------------------------------------------
_sep
echo "  [4] Pip Packages"
_sep
for pkg in numpy pandas scipy sklearn matplotlib plotly PIL streamlit \
           sqlalchemy requests yaml pydantic openpyxl jinja2 dotenv \
           click rich loguru pytest; do
  _check_python_import "${pkg}" "${pkg}"
done
_check_python_import "sqlite3 (stdlib)" "sqlite3"

# ---------------------------------------------------------------------------
# 5. Developer tools
# ---------------------------------------------------------------------------
_sep
echo "  [5] Developer Tools"
_sep

# Conan
if command -v conan &>/dev/null; then
  _check_bin "conan 2.27.0" conan --version
else
  _skip "conan (not installed)"
fi

# SQLite
if command -v sqlite3 &>/dev/null; then
  _check_bin "sqlite3" sqlite3 --version
else
  _skip "sqlite3 (not installed)"
fi

# 7zip
if [[ "${OS}" == "windows" ]]; then
  SEVENZ="${PREFIX}/7zip/7za.exe"
  [[ -f "${SEVENZ}" ]] && _ok "7zip 7za.exe" || _skip "7zip (not installed)"
else
  if command -v 7zz &>/dev/null; then
    VER="$(7zz | head -2 | tail -1 | awk '{print $3}' 2>/dev/null || echo "unknown")"
    _ok "7zip (7zz) ${VER}"
    (( PASS++ )) || true
  else
    _skip "7zip (not installed)"
  fi
fi

# Servy (Windows only)
if [[ "${OS}" == "windows" ]]; then
  SERVY_BIN="${PREFIX}/servy/servy-cli.exe"
  [[ -f "${SERVY_BIN}" ]] && _ok "servy-cli.exe" || _skip "servy (not installed)"
else
  _na "servy (Windows only)"
fi

# ---------------------------------------------------------------------------
# 6. Style formatter
# ---------------------------------------------------------------------------
_sep
echo "  [6] Style Formatter"
_sep
HOOK="${REPO_ROOT}/.git/hooks/pre-commit"
[[ -f "${HOOK}" ]] && _ok "pre-commit hook installed" || _fail "pre-commit hook missing"
_check_bin_receipt "clang-format (hook)" "toolchains/clang/source-build" clang-format --version

# ---------------------------------------------------------------------------
# 7. Python sanity check
# ---------------------------------------------------------------------------
_sep
echo "  [7] Python Sanity Check"
_sep
if ! _receipt_exists "python"; then
  _skip "full package import test (python not installed)"
elif [[ -f "${PY_BIN}" ]]; then
  SANITY_OUT="$("${PY_BIN}" -c "
import sqlite3, numpy, pandas, streamlit, sqlalchemy
print('sqlite3:', sqlite3.sqlite_version)
print('numpy:', numpy.__version__)
print('pandas:', pandas.__version__)
print('streamlit:', streamlit.__version__)
print('sqlalchemy:', sqlalchemy.__version__)
" 2>&1)"
  if [[ $? -eq 0 ]]; then
    _ok "full package import test"
    if [[ "${VERBOSE}" == "true" ]]; then
      echo "${SANITY_OUT}" | while IFS= read -r line; do
        echo "         ${line}"
      done
    fi
  else
    _fail "full package import test"
    echo "${SANITY_OUT}" >&2
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo "  Results"
echo "================================================================================"
echo ""
printf "  Platform : %s\n" "${OS}"
echo ""
printf "  Passed   : %d\n"  "${PASS}"
printf "  Failed   : %d\n"  "${FAIL}"
printf "  Skipped  : %-4d  (not installed -- run the installer first)\n" "${SKIP}"
printf "  N/A      : %-4d  (not applicable on %s)\n" "${NA}" "${OS}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo "  [!!] ${FAIL} test(s) failed."
  echo ""
  exit 1
fi

echo "  All tests passed."
echo ""
exit 0