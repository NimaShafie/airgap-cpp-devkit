#!/usr/bin/env bash
# conan-airgap/scripts/lib/conan-airgap.sh
# Shared helpers for the offline Conan porting kit.
# Source this file; do not execute directly.
# Portable across Git Bash (MINGW64) on Windows and Bash 4.x on RHEL/Rocky 8/9/10.

[[ -n "${_CONAN_AIRGAP_LIB:-}" ]] && return 0
_CONAN_AIRGAP_LIB=1

# The Conan release this kit is built and tested against. The mechanics
# (cache save/restore, config install) are stable across Conan 2.x, so a
# different 2.x is a warning, not a hard failure.
CONAN_TARGET_VERSION="2.30.0"

# ── Logging ─────────────────────────────────────────────────────────────────
ca_log()  { printf '\n==> %s\n' "$*"; }
ca_ok()   { printf '    [OK] %s\n' "$*"; }
ca_warn() { printf '    [WARN] %s\n' "$*" >&2; }
ca_err()  { printf '\nERROR: %s\n' "$*" >&2; }
ca_die()  { ca_err "$*"; exit 1; }

# ── Paths ───────────────────────────────────────────────────────────────────
# Kit root = two levels up from this lib (scripts/lib/ -> kit root).
ca_kit_root() {
    (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}

ca_os() {
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*) echo "linux" ;;
        Darwin*) echo "macos" ;;
        *) echo "unknown" ;;
    esac
}

# ── Conan discovery ─────────────────────────────────────────────────────────
# Locate the conan executable: PATH first, then the devkit install prefixes.
# Handles both the bin/ layout and a PyInstaller onedir at the prefix root, on
# Windows (conan.exe) and Linux (conan).
ca_find_conan() {
    if command -v conan &>/dev/null; then command -v conan; return 0; fi
    local base c
    for base in \
        "${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/conan" \
        "/opt/airgap-cpp-devkit/conan" \
        "${HOME}/.local/share/airgap-cpp-devkit/conan"; do
        for c in "$base/bin/conan" "$base/bin/conan.exe" "$base/conan" "$base/conan.exe"; do
            [[ -x "$c" ]] && { echo "$c"; return 0; }
        done
    done
    return 1
}

# Sets CONAN (path) and CONAN_VERSION; warns on a version other than the target.
ca_require_conan() {
    CONAN="$(ca_find_conan)" || ca_die "conan not found. Install it first (devkit: tools/dev-tools/conan/setup.sh)."
    CONAN_VERSION="$("$CONAN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [[ -z "$CONAN_VERSION" ]] && ca_die "could not determine Conan version from: $CONAN"
    if [[ "$CONAN_VERSION" != "$CONAN_TARGET_VERSION" ]]; then
        ca_warn "Conan ${CONAN_VERSION} detected; this kit targets ${CONAN_TARGET_VERSION}. Continuing (2.x compatible)."
    fi
    ca_ok "Conan ${CONAN_VERSION} at ${CONAN}"
    export CONAN CONAN_VERSION
}

# ── Integrity ───────────────────────────────────────────────────────────────
ca_sha256() {
    if command -v sha256sum &>/dev/null; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then shasum -a 256 "$1" | awk '{print $1}'
    else echo ""; fi
}

# ca_verify_sha256 FILE EXPECTED — abort on mismatch; skip if no tool/expected.
ca_verify_sha256() {
    local file="$1" expected="$2" actual
    [[ -z "$expected" ]] && { ca_warn "no checksum recorded for $(basename "$file"); skipping verify"; return 0; }
    actual="$(ca_sha256 "$file")"
    [[ -z "$actual" ]] && { ca_warn "no sha256 tool; skipping verify for $(basename "$file")"; return 0; }
    if [[ "${actual,,}" != "${expected,,}" ]]; then
        ca_die "checksum mismatch for $(basename "$file")
       expected: ${expected}
       actual:   ${actual}"
    fi
    ca_ok "sha256 verified: $(basename "$file")"
}

ca_timestamp() { date -u +"%Y%m%d-%H%M%S"; }
