#!/usr/bin/env bash
# Build the Go devkit server for Windows amd64 and Linux amd64.
# Run from the repo root: bash scripts/internal/build-server.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVER_DIR="$REPO_ROOT/server"
OUT_DIR="$REPO_ROOT/prebuilt/bin"

# On MINGW64/Git Bash, Go may live in Program Files but not be on the bash PATH
for _d in "/c/Program Files/Go/bin" "/c/Go/bin" "$HOME/go/bin" "/usr/local/go/bin"; do
  [[ -x "$_d/go" || -x "$_d/go.exe" ]] && export PATH="$PATH:$_d" && break
done

if ! command -v go &>/dev/null; then
  echo "ERROR: 'go' is not on PATH. Install Go 1.21+ to build the server." >&2
  exit 1
fi

GO_VER="$(go version)"
echo "Go: $GO_VER"
echo "Building devkit server → $OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$SERVER_DIR"

# Air-gap build: use vendored deps when available, otherwise fail fast with a
# clear message rather than silently reaching out to the internet.
BUILD_FLAGS=(-ldflags="-s -w")
if [[ -d "$SERVER_DIR/vendor" ]]; then
  BUILD_FLAGS+=(-mod=vendor)
else
  # No vendor directory — warn before any network call is attempted.
  if [[ "${GOPROXY:-}" == "off" ]]; then
    echo "ERROR: server/vendor/ not found and GOPROXY=off (air-gap mode)." >&2
    echo "       Run 'go mod vendor' once while online, commit the vendor/" >&2
    echo "       directory, then retry." >&2
    exit 1
  fi
  echo "  [!!]  server/vendor/ not found — downloading module deps (requires network)."
  echo "        For air-gapped builds: run 'go mod vendor' once, commit vendor/"
  go mod download
fi

# Build into a temp dir, then move into place. Writing directly into
# prebuilt/bin would dirty the working tree between the two builds, so the second
# binary's embedded vcs stamp would read modified=true even from a clean commit.
# Staging keeps both builds reading the same clean tree → reproducible stamps.
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT

echo ""
echo "Building devkit-server-linux-amd64 ..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build "${BUILD_FLAGS[@]}" -o "$TMP_OUT/devkit-server-linux-amd64" .

echo "Building devkit-server-windows-amd64.exe ..."
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
  go build "${BUILD_FLAGS[@]}" -o "$TMP_OUT/devkit-server-windows-amd64.exe" .

mkdir -p "$OUT_DIR"
mv "$TMP_OUT"/devkit-server-linux-amd64 "$TMP_OUT"/devkit-server-windows-amd64.exe "$OUT_DIR/"
echo "  → $OUT_DIR/devkit-server-linux-amd64"
echo "  → $OUT_DIR/devkit-server-windows-amd64.exe"

echo ""
echo "Build complete."
ls -lh "$OUT_DIR"/devkit-server-*
