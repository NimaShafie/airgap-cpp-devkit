#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/matlab/scripts/check-toolboxes.sh
#
# Verifies that MATLAB is installed and that required toolboxes are licensed
# and present: Database Toolbox and MATLAB Compiler.
#
# USAGE:
#   bash scripts/check-toolboxes.sh [matlab_executable_path]
#
# EXIT CODES:
#   0  -- all checks passed
#   1  -- one or more checks failed
# =============================================================================
set -euo pipefail

MATLAB_EXE="${1:-}"

OS="linux"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac

# ---------------------------------------------------------------------------
# Locate MATLAB executable
# ---------------------------------------------------------------------------
_find_matlab() {
  # User-supplied path
  if [[ -n "${MATLAB_EXE}" ]]; then
    if [[ -f "${MATLAB_EXE}" ]]; then
      echo "${MATLAB_EXE}"
      return 0
    else
      echo "[ERROR] Specified MATLAB path not found: ${MATLAB_EXE}" >&2
      return 1
    fi
  fi

  # On PATH
  if command -v matlab &>/dev/null; then
    command -v matlab
    return 0
  fi

  # Common Windows install locations
  if [[ "${OS}" == "windows" ]]; then
    for base in \
      "/c/Program Files/MATLAB" \
      "${PROGRAMFILES:-/c/Program Files}/MATLAB"; do
      if [[ -d "${base}" ]]; then
        local found
        found="$(find "${base}" -maxdepth 3 -name "matlab.exe" 2>/dev/null | sort -rV | head -1)"
        if [[ -n "${found}" ]]; then
          echo "${found}"
          return 0
        fi
      fi
    done
  fi

  # Common Linux install locations
  if [[ "${OS}" == "linux" ]]; then
    for candidate in \
      /usr/local/MATLAB/*/bin/matlab \
      /opt/MATLAB/*/bin/matlab \
      /opt/matlab/*/bin/matlab; do
      for match in ${candidate}; do
        if [[ -f "${match}" ]]; then
          echo "${match}"
          return 0
        fi
      done
    done
  fi

  return 1
}

echo "------------------------------------------------------------"
echo " [1/3] Checking MATLAB installation..."
echo "------------------------------------------------------------"

MATLAB_BIN=""
if MATLAB_BIN="$(_find_matlab)"; then
  echo "  [OK]  MATLAB found: ${MATLAB_BIN}"
else
  echo ""
  echo "  [FAIL] MATLAB executable not found." >&2
  echo ""
  echo "  MATLAB must be installed before running this script." >&2
  echo "  Install MATLAB via the MathWorks installer:" >&2
  echo "    https://www.mathworks.com/help/install/" >&2
  echo ""
  echo "  If MATLAB is installed but not on PATH, specify its location:" >&2
  if [[ "${OS}" == "windows" ]]; then
    echo "    bash dev-tools/matlab/setup.sh --matlab-path \"/c/Program Files/MATLAB/R2025a/bin/matlab.exe\"" >&2
  else
    echo "    bash dev-tools/matlab/setup.sh --matlab-path /usr/local/MATLAB/R2025a/bin/matlab" >&2
  fi
  exit 0
fi

# Get MATLAB version
MATLAB_VER="$("${MATLAB_BIN}" -batch "disp(version)" 2>/dev/null | head -1 | tr -d '\r' || echo "unknown")"
echo "  [OK]  MATLAB version: ${MATLAB_VER}"

echo ""
echo "------------------------------------------------------------"
echo " [2/3] Checking Database Toolbox..."
echo "------------------------------------------------------------"

# Run MATLAB in batch mode to check toolbox license
DB_CHECK="$("${MATLAB_BIN}" -batch "
  tb = ver('database');
  if isempty(tb)
    fprintf('NOT_FOUND\n');
  else
    v = tb(1);
    fprintf('FOUND %s %s\n', v.Name, v.Version);
  end
  exit
" 2>/dev/null | grep -E "^(FOUND|NOT_FOUND)" | head -1 | tr -d '\r' || echo "ERROR")"

case "${DB_CHECK}" in
  FOUND*)
    echo "  [OK]  Database Toolbox: ${DB_CHECK#FOUND }"
    ;;
  NOT_FOUND)
    echo ""
    echo "  [FAIL] Database Toolbox not found." >&2
    echo ""
    echo "  The Database Toolbox must be licensed and installed via the" >&2
    echo "  MathWorks installer alongside MATLAB." >&2
    echo ""
    echo "  To add it to an existing MATLAB install:" >&2
    echo "    1. Open the MathWorks installer" >&2
    echo "    2. Select 'Add Products to an Existing Installation'" >&2
    echo "    3. Select 'Database Toolbox' and complete installation" >&2
    echo ""
    echo "  License required: Database Toolbox is a separately licensed" >&2
    echo "  toolbox -- contact your MathWorks license administrator." >&2
    exit 1
    ;;
  *)
    echo "  [!!]  Could not determine Database Toolbox status (MATLAB batch mode failed)." >&2
    echo "        This may indicate a license server issue or MATLAB path problem." >&2
    echo "        Run manually: matlab -batch \"ver database\"" >&2
    exit 1
    ;;
esac

echo ""
echo "------------------------------------------------------------"
echo " [3/3] Checking MATLAB Compiler..."
echo "------------------------------------------------------------"

COMPILER_CHECK="$("${MATLAB_BIN}" -batch "
  tb = ver('compiler');
  if isempty(tb)
    fprintf('NOT_FOUND\n');
  else
    v = tb(1);
    fprintf('FOUND %s %s\n', v.Name, v.Version);
  end
  exit
" 2>/dev/null | grep -E "^(FOUND|NOT_FOUND)" | head -1 | tr -d '\r' || echo "ERROR")"

case "${COMPILER_CHECK}" in
  FOUND*)
    echo "  [OK]  MATLAB Compiler: ${COMPILER_CHECK#FOUND }"
    ;;
  NOT_FOUND)
    echo ""
    echo "  [FAIL] MATLAB Compiler not found." >&2
    echo ""
    echo "  The MATLAB Compiler must be licensed and installed via the" >&2
    echo "  MathWorks installer alongside MATLAB." >&2
    echo ""
    echo "  To add it to an existing MATLAB install:" >&2
    echo "    1. Open the MathWorks installer" >&2
    echo "    2. Select 'Add Products to an Existing Installation'" >&2
    echo "    3. Select 'MATLAB Compiler' and complete installation" >&2
    echo ""
    echo "  License required: MATLAB Compiler is separately licensed." >&2
    exit 1
    ;;
  *)
    echo "  [!!]  Could not determine MATLAB Compiler status." >&2
    echo "        Run manually: matlab -batch \"ver compiler\"" >&2
    exit 1
    ;;
esac

echo ""
echo "============================================================"
echo " All MATLAB checks passed."
echo "  MATLAB      : ${MATLAB_BIN}"
echo "  Version     : ${MATLAB_VER}"
echo "  DB Toolbox  : present"
echo "  Compiler    : present"
echo "============================================================"