#!/usr/bin/env bash
# Copy prebuilt server binaries into the Python package before building the wheel.
# Run from the repo root: bash packages/python/scripts/stage-binaries.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BIN_SRC="$REPO_ROOT/prebuilt/bin"
BIN_DST="$REPO_ROOT/packages/python/src/airgap_devkit/bin"
GO_MOD="$REPO_ROOT/server/go.mod"

# Return the declared version for a module path from go.mod ("" if absent).
declared_version() {
    awk -v mod="$1" '$1==mod {print $2}' "$GO_MOD" | head -1
}

# True when have >= want using version sort, so a newer build never trips.
version_ge() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]
}

# Guard against shipping a binary older than the patched source: read the
# toolchain and key dependency versions embedded in the built binary and refuse
# to stage one that lags what go.mod declares. Without a "go" toolchain we can
# only warn — the release host is expected to have it.
verify_not_stale() {
    local bin="$1"
    if ! command -v go >/dev/null 2>&1; then
        echo "  WARN: 'go' not found — cannot verify $bin embedded versions" >&2
        return 0
    fi
    local info want_go got_go want_text got_text
    info="$(go version -m "$bin" 2>/dev/null)" || { echo "  WARN: cannot read build info from $bin" >&2; return 0; }

    want_go="$(awk '$1=="go"{print $2}' "$GO_MOD" | head -1)"
    got_go="$(printf '%s\n' "$info" | awk 'NR==1{print $2}' | sed 's/^go//')"
    if [[ -n "$want_go" && -n "$got_go" ]] && ! version_ge "$got_go" "$want_go"; then
        echo "STALE: $bin built with go$got_go but go.mod requires go$want_go — rebuild before release" >&2
        exit 1
    fi

    want_text="$(declared_version golang.org/x/text)"
    got_text="$(printf '%s\n' "$info" | awk '$1=="dep" && $2=="golang.org/x/text"{print $3}' | head -1)"
    if [[ -n "$want_text" && -n "$got_text" ]] && ! version_ge "$got_text" "$want_text"; then
        echo "STALE: $bin links golang.org/x/text $got_text but go.mod pins $want_text — rebuild before release" >&2
        exit 1
    fi
    echo "  verified: $bin (go$got_go, x/text ${got_text:-n/a})"
}

for binary in \
    "devkit-server-linux-amd64" \
    "devkit-server-windows-amd64.exe"; do

    src="$BIN_SRC/$binary"
    if [[ ! -f "$src" ]]; then
        echo "MISSING: $src — run 'bash scripts/internal/build-server.sh' first" >&2
        exit 1
    fi
    cp "$src" "$BIN_DST/$binary"
    echo "  staged: $binary"
    verify_not_stale "$BIN_DST/$binary"
done

echo ""
echo "Binaries staged. Build the wheel with:"
echo "  pip install build"
echo "  python -m build packages/python/ --outdir dist/python/"
