#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# launch.sh -- airgap-cpp-devkit primary entry point (v2 — Go server)
#
# Starts the DevKit Manager web UI using a pre-compiled Go binary.
# No Python, no pip, no runtime dependencies.
#
# USAGE:
#   bash launch.sh                      # launch UI and open browser
#   bash launch.sh --port 9090          # custom port
#   bash launch.sh --host 0.0.0.0       # bind to all interfaces
#   bash launch.sh --no-browser         # start server, don't open browser
#   bash launch.sh --cli                # skip UI, run install-cli.sh directly
#   bash launch.sh --rebuild            # rebuild binary from source, then launch
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT_BIN="${SCRIPT_DIR}/prebuilt/bin"
INSTALL_SH="${SCRIPT_DIR}/install-cli.sh"

_sep() { printf '%s\n' "================================================================================"; }

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
FORCE_CLI=false
FORCE_REBUILD=false
NO_BROWSER=false
SERVER_ARGS=()
UI_PORT=8080
UI_HOST="127.0.0.1"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli)        FORCE_CLI=true; shift ;;
        --rebuild)    FORCE_REBUILD=true; shift ;;
        --port)       UI_PORT="$2";  SERVER_ARGS+=("$1" "$2"); shift 2 ;;
        --host)       UI_HOST="$2";  SERVER_ARGS+=("$1" "$2"); shift 2 ;;
        --no-browser) NO_BROWSER=true; SERVER_ARGS+=("$1"); shift ;;
        *)            SERVER_ARGS+=("$1"); shift ;;
    esac
done

# ---------------------------------------------------------------------------
# --cli: go straight to install-cli.sh
# ---------------------------------------------------------------------------
if [[ "${FORCE_CLI}" == "true" ]]; then
    exec bash "${INSTALL_SH}" "${SERVER_ARGS[@]+"${SERVER_ARGS[@]}"}"
fi

# ---------------------------------------------------------------------------
# Pick binary for current platform
# ---------------------------------------------------------------------------
_os_type() {
    if [[ "${OS:-}" == "Windows_NT" ]] || [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || \
       [[ "$(uname -s 2>/dev/null)" == MSYS* ]] || [[ "$(uname -s 2>/dev/null)" == CYGWIN* ]]; then
        echo "windows"
    else
        echo "linux"
    fi
}

PLATFORM="$(_os_type)"
if [[ "$PLATFORM" == "windows" ]]; then
    SERVER_BIN="${PREBUILT_BIN}/devkit-server-windows-amd64.exe"
else
    SERVER_BIN="${PREBUILT_BIN}/devkit-server-linux-amd64"
fi

# ---------------------------------------------------------------------------
# --rebuild: explicitly build from source before launching
# ---------------------------------------------------------------------------
if [[ "${FORCE_REBUILD}" == "true" ]]; then
    # Add common Go install locations to PATH (needed in Git Bash / MINGW64)
    for _d in "/c/Program Files/Go/bin" "/c/Go/bin" "$HOME/go/bin" "/usr/local/go/bin"; do
        [[ -x "$_d/go" || -x "$_d/go.exe" ]] && export PATH="$PATH:$_d" && break
    done
    if ! command -v go &>/dev/null 2>&1; then
        echo "  [!!]  --rebuild requires Go 1.21+ on PATH. Install Go or omit --rebuild to use prebuilt." >&2
        exit 1
    fi
    bash "${SCRIPT_DIR}/scripts/build-server.sh"
    echo ""
fi

# ---------------------------------------------------------------------------
# Check binary exists
# ---------------------------------------------------------------------------
if [[ ! -f "${SERVER_BIN}" ]]; then
    echo ""
    _sep
    echo "  airgap-cpp-devkit -- Launcher"
    _sep
    echo ""
    echo "  [!!]  Server binary not found:"
    echo "        ${SERVER_BIN}"
    echo ""
    echo "  Initialise the prebuilt submodule:"
    echo "        git submodule update --init --recursive prebuilt"
    echo ""
    echo "  Falling back to install-cli.sh..."
    echo ""
    exec bash "${INSTALL_SH}"
fi

# ---------------------------------------------------------------------------
# Free target port if in use
# ---------------------------------------------------------------------------
_free_port() {
    local port="$1"
    local pids
    pids="$(netstat -ano 2>/dev/null \
        | grep -E "[:.]${port}[[:space:]].*LISTEN" \
        | awk '{print $NF}' \
        | sort -u)" || true
    [[ -z "$pids" ]] && return 0
    echo "  [!!]  Port ${port} in use — killing: ${pids}"
    for pid in $pids; do
        if [[ "$PLATFORM" == "windows" ]]; then
            taskkill.exe //PID "$pid" //F 2>/dev/null || true
        else
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    sleep 1
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
echo ""
_sep
echo "  airgap-cpp-devkit -- DevKit Manager v2"
_sep
echo "  Platform : ${PLATFORM}"
echo "  Binary   : ${SERVER_BIN}"
echo "  Press Ctrl+C to stop."
_sep
echo ""

# Read effective port from devkit.config.json using pure bash (no python needed)
_effective_port() {
    local cfg="${SCRIPT_DIR}/devkit.config.json"
    if [[ -f "$cfg" ]]; then
        local p
        p="$(grep -oE '"port"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" 2>/dev/null \
             | grep -oE '[0-9]+$' | head -1)"
        [[ -n "$p" ]] && echo "$p" && return
    fi
    echo "${UI_PORT}"
}
EFFECTIVE_PORT="$(_effective_port)"
_free_port "${EFFECTIVE_PORT}"

# Fork a background job to open the browser — this survives exec below.
# 2-second delay gives the server time to bind its port first.
if [[ "${NO_BROWSER}" != "true" ]]; then
    OPEN_URL="http://${UI_HOST}:${EFFECTIVE_PORT}"
    (
        sleep 2
        if [[ "${PLATFORM}" == "windows" ]]; then
            powershell.exe -NoProfile -Command "Start-Process '${OPEN_URL}'" 2>/dev/null || \
            cmd.exe /c start "${OPEN_URL}" 2>/dev/null || true
        else
            xdg-open "${OPEN_URL}" 2>/dev/null || \
            gnome-open "${OPEN_URL}" 2>/dev/null || true
        fi
    ) &
fi

chmod +x "${SERVER_BIN}" 2>/dev/null || true

# Always pass --no-browser to the binary; the shell handles opening above.
exec "${SERVER_BIN}" \
    --tools    "${SCRIPT_DIR}/tools" \
    --prebuilt "${SCRIPT_DIR}/prebuilt" \
    --no-browser \
    "${SERVER_ARGS[@]+"${SERVER_ARGS[@]}"}"
