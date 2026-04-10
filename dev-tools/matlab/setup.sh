#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/matlab/setup.sh
#
# Verifies that MATLAB and required toolboxes are installed and accessible.
# Does NOT install MATLAB -- it must already be present on the system.
# Verifies: MATLAB base, Database Toolbox, MATLAB Compiler.
#
# USAGE:
#   bash dev-tools/matlab/setup.sh [--check-only] [--matlab-path <path>]
#
# OPTIONS:
#   --check-only            Print status without registering env or receipt
#   --matlab-path <path>    Path to MATLAB executable (if not on PATH)
#
# PLATFORMS:
#   Windows 11  (Git Bash / MINGW64)
#   RHEL 8 / Linux x86_64
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

CHECK_ONLY=false
MATLAB_PATH_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)       CHECK_ONLY=true; shift ;;
    --matlab-path)      MATLAB_PATH_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^[^#]/{/^#/!q; s/^# \?//; p}' "$0"
      exit 0 ;;
        --rebuild) shift ;; # no-op: matlab check reruns by default
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  Linux*)                OS="linux"   ;;
  *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

echo ""
echo "============================================================"
echo " MATLAB -- Installation Check"
echo " Platform : ${OS}"
echo " Date     : $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Run toolbox check script
# ---------------------------------------------------------------------------
bash "${SCRIPTS_DIR}/check-toolboxes.sh" "${MATLAB_PATH_OVERRIDE}"
CHECK_EXIT=$?

if [[ "${CHECK_EXIT}" -ne 0 ]]; then
  echo ""
  echo "  [FAIL] MATLAB verification failed."
  echo "         See output above for details."
  exit 1
fi

echo ""
echo "  [OK]  MATLAB verification passed."
echo ""

if [[ "${CHECK_ONLY}" == "true" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Source install-mode and write receipt if not check-only
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "matlab" "system"

# Locate matlab executable for receipt
MATLAB_BIN="${MATLAB_PATH_OVERRIDE}"
if [[ -z "${MATLAB_BIN}" ]]; then
  MATLAB_BIN="$(command -v matlab 2>/dev/null || echo "not found")"
fi

install_receipt_write "success" "matlab:${MATLAB_BIN}"
install_mode_print_footer "success" "matlab:${MATLAB_BIN}"