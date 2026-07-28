#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# serve.sh -- host the DevKit Manager for a whole team (Mode 1: shared server)
#
# Runs the devkit-ui bound to a network interface so team members can reach it
# from their own machines, prints the token-authenticated access URL to share,
# and (optionally) enables HTTPS. Tools installed through this server land on
# THIS host — see docs/DEPLOYMENT.md for the shared-host model.
#
# For a single user with no admin rights, use scripts/launch.sh instead
# (localhost, per-user install). See docs/DEPLOYMENT.md Mode 2.
#
# USAGE:
#   bash scripts/serve.sh --tls                  # HTTPS on all interfaces
#   bash scripts/serve.sh --port 9090 --tls      # HTTPS on a custom port
#   bash scripts/serve.sh --advertise devbox.corp.local --tls
#
# Binding to a network interface without --tls is refused unless you pass
# --insecure, so the access token is never sent in the clear by default.
#
# OPTIONS:
#   --host <addr>       Interface to bind (default: 0.0.0.0 = all interfaces)
#   --advertise <name>  Hostname/IP to put in the shared URL
#                       (default: auto-detected LAN address)
#   --port <n>          Port (default: devkit.config.json port, else 9090)
#   --tls               Serve HTTPS with an auto-generated self-signed cert
#   --insecure          Allow plaintext HTTP on a network interface (trusted LAN)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BIND_HOST="0.0.0.0"
ADVERTISE=""
PORT=""
TLS=false
INSECURE=false
PASS_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)      BIND_HOST="$2"; shift 2 ;;
        --advertise) ADVERTISE="$2"; shift 2 ;;
        --port)      PORT="$2"; shift 2 ;;
        --tls)       TLS=true; shift ;;
        --insecure)  INSECURE=true; shift ;;
        -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           PASS_ARGS+=("$1"); shift ;;
    esac
done

# --- Effective port: --port > config > 9090 -------------------------------
if [[ -z "$PORT" ]]; then
    PORT="$(grep -oE '"port"[[:space:]]*:[[:space:]]*[0-9]+' "${REPO_ROOT}/devkit.config.json" 2>/dev/null \
        | grep -oE '[0-9]+$' | head -1)"
    PORT="${PORT:-9090}"
fi

# --- Ensure a stable auth token exists so we can print the URL up front ----
TOKEN_FILE="${REPO_ROOT}/.devkit-token"
if [[ ! -s "$TOKEN_FILE" ]]; then
    if command -v openssl &>/dev/null; then
        TOKEN="$(openssl rand -hex 32)"
    elif [[ -r /dev/urandom ]]; then
        TOKEN="$(head -c32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    else
        echo "ERROR: cannot generate a token (no openssl or /dev/urandom)." >&2; exit 1
    fi
    printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE" 2>/dev/null || true
fi
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

# --- Figure out a reachable address for the shared URL --------------------
detect_ip() {
    local ip=""
    if command -v hostname &>/dev/null && hostname -I >/dev/null 2>&1; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    if [[ -z "$ip" ]] && command -v ipconfig >/dev/null 2>&1; then
        ip="$(ipconfig 2>/dev/null | grep -iE 'IPv4' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^127\.' | head -1)"
    fi
    [[ -z "$ip" ]] && ip="$(hostname 2>/dev/null || echo '<server-address>')"
    echo "$ip"
}
[[ -z "$ADVERTISE" ]] && ADVERTISE="$(detect_ip)"

SCHEME="http"; $TLS && SCHEME="https"

# Refuse to expose the UI unencrypted on a network interface unless the operator
# explicitly opts in. A team server binds beyond loopback, so plaintext there
# would put the access token on the wire for anyone on the segment.
case "$BIND_HOST" in
    127.0.0.1|localhost|::1|"") LOOPBACK=true ;;
    *)                          LOOPBACK=false ;;
esac
if ! $TLS && ! $LOOPBACK && ! $INSECURE; then
    echo "ERROR: refusing to serve unencrypted HTTP on ${BIND_HOST} (a network interface)." >&2
    echo "       Add --tls to enable HTTPS, or --insecure to override on a trusted network." >&2
    exit 1
fi

ACCESS_URL="${SCHEME}://${ADVERTISE}:${PORT}/auth/bootstrap?devkit_token=${TOKEN}&next=/"

# The access URL embeds the token, so never emit it where a log collector would
# capture it (e.g. the systemd journal). Write it to an owner-only file, and
# print it to the console only when attached to an interactive terminal.
URL_FILE="${REPO_ROOT}/.devkit-access-url"
( umask 077; printf '%s\n' "$ACCESS_URL" > "$URL_FILE" )
chmod 600 "$URL_FILE" 2>/dev/null || true

echo ""
echo "================================================================================"
echo "  airgap-cpp-devkit -- Team Server (Mode 1)"
echo "================================================================================"
echo "  Binding    : ${BIND_HOST}:${PORT}   (${SCHEME})"
if [[ -t 1 ]]; then
    echo "  Share this with your team (token-authenticated, one click):"
    echo ""
    echo "      ${ACCESS_URL}"
else
    echo "  Access URL (contains the token) written to an owner-only file:"
    echo "      ${URL_FILE}"
    echo "  Reveal it with:  cat ${URL_FILE}"
fi
echo ""
echo "  Notes:"
echo "   - Tools installed via this UI land on THIS host (shared-host model)."
echo "   - The token grants access. Rotate by deleting .devkit-token."
$TLS || echo "   - Serving unencrypted HTTP (--insecure). Add --tls for HTTPS on untrusted networks."
echo "   - Ctrl+C to stop."
echo "================================================================================"
echo ""

# --- Best-effort firewall reachability check --------------------------------
# A team server binds beyond loopback, but the host firewall may still drop the
# port — so the shareable URL just printed can be unreachable from a LAN/VLAN
# peer with no hint as to why. Probe the common Linux firewalls and warn (never
# fail: the check is advisory and cannot see upstream network ACLs).
_warn_firewall() {
    $LOOPBACK && return 0            # loopback bind is never firewalled
    case "$BIND_HOST" in *:*) return 0 ;; esac  # skip IPv6 literal parsing

    local blocked=""
    if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
        if ! firewall-cmd --query-port="${PORT}/tcp" &>/dev/null; then
            blocked="firewalld"
        fi
    elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qi 'Status: active'; then
        if ! ufw status 2>/dev/null | grep -qE "(^|[[:space:]])${PORT}(/tcp)?[[:space:]]+(ALLOW|ACCEPT)"; then
            blocked="ufw"
        fi
    fi

    if [[ -n "$blocked" ]]; then
        echo "  [!!] ${blocked} appears to be active and port ${PORT}/tcp is not open."
        echo "       Team members on the LAN may not be able to reach the URL above."
        if [[ "$blocked" == "firewalld" ]]; then
            echo "       Open it (as admin):  firewall-cmd --add-port=${PORT}/tcp   (add --permanent to persist)"
        else
            echo "       Open it (as admin):  ufw allow ${PORT}/tcp"
        fi
        echo ""
    fi
}
_warn_firewall

LAUNCH_ARGS=(--host "$BIND_HOST" --port "$PORT" --no-browser)
$TLS && LAUNCH_ARGS+=(--tls)
exec bash "${SCRIPT_DIR}/launch.sh" "${LAUNCH_ARGS[@]}" "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}"
