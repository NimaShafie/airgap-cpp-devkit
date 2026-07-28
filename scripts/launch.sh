#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# launch.sh -- airgap-cpp-devkit primary entry point
#
# Starts the DevKit Manager web UI using a pre-compiled Go binary.
# No Python, no pip, no runtime dependencies.
#
# USAGE:
#   bash scripts/launch.sh                      # launch UI and open browser
#   bash scripts/launch.sh --port 9090          # custom port
#   bash scripts/launch.sh --host 0.0.0.0       # bind to all interfaces
#   bash scripts/launch.sh --no-browser         # start server, don't open browser
#   bash scripts/launch.sh --cli                # skip UI, run scripts/internal/install-cli.sh directly
#   bash scripts/launch.sh --rebuild            # rebuild binary from source, then launch
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREBUILT_BIN="${REPO_ROOT}/prebuilt/bin"
INSTALL_SH="${SCRIPT_DIR}/internal/install-cli.sh"

_sep() { printf '%s\n' "================================================================================"; }

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
FORCE_CLI=false
FORCE_REBUILD=false
SERVER_ARGS=()
INSTALL_ARGS=()
UI_PORT=9090
USER_PORT=""   # explicit --port flag; takes priority over config file

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli)         FORCE_CLI=true; shift ;;
        --rebuild)     FORCE_REBUILD=true; INSTALL_ARGS+=("$1"); shift ;;
        --port)        UI_PORT="$2"; USER_PORT="$2"; shift 2 ;;
        --host)        SERVER_ARGS+=("$1" "$2"); shift 2 ;;
        --no-browser)  SERVER_ARGS+=("$1"); shift ;;
        --yes|--admin) INSTALL_ARGS+=("$1"); shift ;;
        --profile|--prefix) INSTALL_ARGS+=("$1" "$2"); shift 2 ;;
        *)             SERVER_ARGS+=("$1"); shift ;;
    esac
done

# ---------------------------------------------------------------------------
# --cli: go straight to install-cli.sh
# ---------------------------------------------------------------------------
if [[ "${FORCE_CLI}" == "true" ]]; then
    exec bash "${INSTALL_SH}" "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}"
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
    bash "${SCRIPT_DIR}/internal/build-server.sh"
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
    exec bash "${INSTALL_SH}" "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}"
fi

# ---------------------------------------------------------------------------
# Free target port if in use — only kills existing devkit-server processes.
# Refuses to kill unrelated daemons to avoid collateral damage.
# ---------------------------------------------------------------------------
_free_port() {
    local port="$1"
    local pids=""
    if [[ "$PLATFORM" == "windows" ]]; then
        pids="$(netstat -ano 2>/dev/null \
            | grep -E "[:.]${port}[[:space:]].*LISTEN" \
            | awk '{print $NF}' \
            | grep -E '^[0-9]+$' \
            | sort -u)" || true
    else
        pids="$(ss -ltnp "sport = :${port}" 2>/dev/null \
            | grep -oP 'pid=\K[0-9]+' \
            | sort -u)" || true
        if [[ -z "$pids" ]] && command -v lsof &>/dev/null; then
            pids="$(lsof -ti ":${port}" 2>/dev/null)" || true
        fi
    fi
    [[ -z "$pids" ]] && return 0

    local killed=0
    for pid in $pids; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if [[ "$PLATFORM" == "windows" ]]; then
            local exe
            exe="$(wmic process where "ProcessId=${pid}" get ExecutablePath 2>/dev/null \
                | grep -i "devkit-server" | tr -d '\r' | xargs || true)"
            if [[ -n "$exe" ]]; then
                echo "  [--]  Stopping previous devkit-server (PID ${pid}) on port ${port}."
                taskkill.exe //PID "$pid" //F 2>/dev/null || true
                killed=1
            else
                echo "  [!!]  Port ${port} is in use by PID ${pid} (not devkit-server)." >&2
                echo "        Free port ${port} manually or choose a different port with --port." >&2
                exit 1
            fi
        else
            local exe
            exe="$(readlink "/proc/${pid}/exe" 2>/dev/null || true)"
            if [[ "$exe" == *devkit-server* ]]; then
                echo "  [--]  Stopping previous devkit-server (PID ${pid}) on port ${port}."
                kill -TERM "$pid" 2>/dev/null || true
                killed=1
            else
                echo "  [!!]  Port ${port} is in use by PID ${pid} ($(basename "${exe:-unknown}")) — not devkit-server." >&2
                echo "        Free port ${port} manually or choose a different port with --port." >&2
                exit 1
            fi
        fi
    done
    [[ "$killed" == "1" ]] && sleep 1
    return 0
}

# ---------------------------------------------------------------------------
# Report whether a port has a listener, WITHOUT needing to identify its owner.
# `ss -ltnp` only reveals the PID of a socket the caller owns, so a standard
# user cannot see (and _free_port cannot act on) a root-owned listener such as
# Cockpit on :9090. This check keys off the listening state alone, so we can
# fail fast with a clear message instead of letting the server bind and die.
# ---------------------------------------------------------------------------
_port_in_use() {
    local port="$1"
    if [[ "$PLATFORM" == "windows" ]]; then
        netstat -ano 2>/dev/null \
            | grep -E "[:.]${port}[[:space:]].*LISTEN" -q && return 0
        return 1
    fi
    if command -v ss &>/dev/null; then
        ss -ltn "sport = :${port}" 2>/dev/null | grep -q "LISTEN" && return 0
        return 1
    fi
    if command -v netstat &>/dev/null; then
        netstat -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]" && return 0
        return 1
    fi
    # No probe tool available — cannot tell; assume free and let bind decide.
    return 1
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
echo ""
_sep
echo "  airgap-cpp-devkit -- DevKit Manager"
_sep
echo "  Platform : ${PLATFORM}"
echo "  Binary   : ${SERVER_BIN}"
echo "  Press Ctrl+C to stop."
_sep
echo ""

# Read effective port: explicit --port flag > devkit.config.json > default (9090)
_effective_port() {
    [[ -n "$USER_PORT" ]] && echo "$USER_PORT" && return
    local cfg="${REPO_ROOT}/devkit.config.json"
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

# _free_port only stops a devkit-server it can see and own. If something else is
# still holding the port (e.g. Cockpit on :9090, or any listener owned by another
# user), the bind would fail *after* the server prints its start-up banner —
# output that reads like success. Detect that here and stop with remediation.
if _port_in_use "${EFFECTIVE_PORT}"; then
    echo ""
    echo "  [!!]  Port ${EFFECTIVE_PORT} is already in use by another process." >&2
    echo "        It is not a devkit-server this launcher can stop (it may be owned" >&2
    echo "        by another user or a system service such as Cockpit)." >&2
    echo "" >&2
    echo "        Start on a different port:   bash scripts/launch.sh --port 9191" >&2
    echo "        Or set \"port\" in devkit.config.json." >&2
    echo "" >&2
    exit 1
fi

chmod +x "${SERVER_BIN}" 2>/dev/null || true

exec "${SERVER_BIN}" \
    --tools    "${REPO_ROOT}/tools" \
    --prebuilt "${REPO_ROOT}/prebuilt" \
    --port     "${EFFECTIVE_PORT}" \
    "${SERVER_ARGS[@]+"${SERVER_ARGS[@]}"}"
