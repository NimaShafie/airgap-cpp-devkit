#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# launch.sh -- airgap-cpp-devkit primary entry point
#
# Preferred way to install and manage devkit tools.
# Finds Python 3.8+, launches the DevKit Manager web UI, and opens the browser.
# Falls back to the interactive CLI installer (install-cli.sh) if Python is absent.
#
# USAGE:
#   bash launch.sh                      # auto-detect; launch UI or CLI fallback
#   bash launch.sh --port 9090          # custom port for the web UI
#   bash launch.sh --host 0.0.0.0       # bind to all interfaces (LAN access)
#   bash launch.sh --no-browser         # start server but don't open browser
#   bash launch.sh --cli                # skip UI, run install-cli.sh directly
#
# WHAT HAPPENS:
#   1. Script searches for Python 3.8+ (python3 / python).
#   2. If found   -> launches manager/devkit.py and opens
#                    http://127.0.0.1:8080 (or --port value).
#                    From there: pick a profile or install tools individually.
#   3. If not found -> falls back to bash install-cli.sh (interactive CLI wizard).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVKIT_UI="${SCRIPT_DIR}/manager/devkit.py"
INSTALL_SH="${SCRIPT_DIR}/install-cli.sh"

# ---------------------------------------------------------------------------
# Plain ASCII display helpers (match install-cli.sh style)
# ---------------------------------------------------------------------------
_sep2() { printf '%s\n' "================================================================================"; }

# ---------------------------------------------------------------------------
# Parse flags: consume --cli; pass everything else through to devkit.py
# ---------------------------------------------------------------------------
FORCE_CLI=false
UI_ARGS=()
UI_PORT=8080
UI_HOST="127.0.0.1"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli)    FORCE_CLI=true; shift ;;
        --port)   UI_PORT="$2";  UI_ARGS+=("$1" "$2"); shift 2 ;;
        --host)   UI_HOST="$2";  UI_ARGS+=("$1" "$2"); shift 2 ;;
        *)        UI_ARGS+=("$1"); shift ;;
    esac
done

# ---------------------------------------------------------------------------
# --cli: skip Python detection, go straight to install-cli.sh
# ---------------------------------------------------------------------------
if [[ "${FORCE_CLI}" == "true" ]]; then
    echo ""
    _sep2
    echo "  airgap-cpp-devkit -- CLI Installer"
    _sep2
    echo ""
    echo "  [--cli] Skipping DevKit Manager. Launching install-cli.sh..."
    echo ""
    exec bash "${INSTALL_SH}" "${UI_ARGS[@]+"${UI_ARGS[@]}"}"
fi

# ---------------------------------------------------------------------------
# Find Python 3.8+
# ---------------------------------------------------------------------------
_find_python() {
    local candidates=(python3 python python3.13 python3.12 python3.11 python3.10 python3.9 python3.8)
    for py in "${candidates[@]}"; do
        if command -v "${py}" &>/dev/null; then
            local ok
            ok="$("${py}" -c 'import sys; print(sys.version_info >= (3,8))' 2>/dev/null || echo "False")"
            if [[ "${ok}" == "True" ]]; then
                echo "${py}"
                return 0
            fi
        fi
    done
    return 1
}

echo ""
_sep2
echo "  airgap-cpp-devkit -- Launcher"
_sep2
echo ""
echo "  Checking for Python 3.8+..."

PYTHON_BIN=""
if PYTHON_BIN="$(_find_python 2>/dev/null)"; then
    PY_VER="$(${PYTHON_BIN} --version 2>&1 | awk '{print $2}')"
    echo "  [OK]  Python ${PY_VER} found  (${PYTHON_BIN})"
    echo ""
    echo "  Starting DevKit Manager..."
    echo "  Open your browser at  http://${UI_HOST}:${UI_PORT}  if it does not open automatically."
    echo "  Press Ctrl+C to stop the server."
    echo ""
    _sep2
    echo ""
    # Standalone Python ships with a ._pth file that overrides sys.path entirely,
    # ignoring both PYTHONPATH env var and cwd. The only reliable path injection
    # is via -c code: sys.path.insert runs before any import, always wins.
    # Use forward slashes in the Windows path — Python accepts them and it avoids
    # backslash-escaping inside the shell double-quoted -c string.
    TOOLS_DIR="${SCRIPT_DIR}/tools"
    PY_SRC="${SCRIPT_DIR}/manager/src"
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
        PY_SRC="$(cygpath -w "${PY_SRC}")"
        PY_SRC="${PY_SRC//\\/\/}"
    fi
    exec "${PYTHON_BIN}" -c \
        "import sys; sys.path.insert(0, '${PY_SRC}'); from airgap_devkit.launcher import main; main()" \
        --tools "${TOOLS_DIR}" \
        "${UI_ARGS[@]+"${UI_ARGS[@]}"}"
else
    echo "  [!!]  Python 3.8+ not found on PATH."
    echo ""
    echo "  The DevKit Manager (web UI) requires Python 3.8+."
    echo ""
    echo "  Falling back to the interactive CLI installer..."
    echo ""
    printf "  Press Enter to continue with install-cli.sh, or Ctrl+C to cancel..."
    read -r
    echo ""
    exec bash "${INSTALL_SH}"
fi
