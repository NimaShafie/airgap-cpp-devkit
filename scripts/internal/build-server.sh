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

# A container runtime lets the Linux binary be built as a musl static-PIE.
CONTAINER=""
if command -v podman &>/dev/null; then
  CONTAINER=podman
elif command -v docker &>/dev/null; then
  CONTAINER=docker
fi

echo ""
echo "Building devkit-server-linux-amd64 ..."
if [[ -n "$CONTAINER" ]]; then
  # Built on Alpine with an external musl linker, the result is a position-
  # independent yet fully static ELF (no dynamic interpreter): it gains ASLR and
  # still runs on both musl and glibc hosts. A plain -buildmode=pie from the
  # pure-Go cross-compile would instead require /lib64/ld-linux, which is absent
  # on Alpine, so the container build is the portable way to get ASLR here.
  echo "  via $CONTAINER (Alpine / musl static-pie)"
  "$CONTAINER" run --rm \
    -v "$SERVER_DIR":/src:ro,Z \
    -v "$TMP_OUT":/out:Z \
    docker.io/golang:alpine sh -c '
      set -e
      apk add --no-cache musl-dev gcc >/dev/null
      cp -a /src /build && cd /build
      gv=$(go env GOVERSION | sed "s/go//"); sed -i "s/^go .*/go ${gv}/" go.mod
      export GOFLAGS=-mod=vendor GOTOOLCHAIN=local
      CGO_ENABLED=1 go build -buildmode=pie \
        -ldflags="-linkmode=external -extldflags=-static-pie -s -w" \
        -o /out/devkit-server-linux-amd64 .
    '
else
  echo "  [!!] No container runtime (podman/docker) found — falling back to a"
  echo "       static, non-PIE Linux build (no ASLR on the main image). Official"
  echo "       releases should be built where podman/docker or CI (Alpine) is"
  echo "       available so the Linux binary ships as a musl static-pie."
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
    go build "${BUILD_FLAGS[@]}" -o "$TMP_OUT/devkit-server-linux-amd64" .
fi

echo "Building devkit-server-windows-amd64.exe ..."
# The Go Windows PE already carries DYNAMICBASE + HIGH_ENTROPY_VA (ASLR) by
# default, so no -buildmode=pie is needed here.
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
  go build "${BUILD_FLAGS[@]}" -o "$TMP_OUT/devkit-server-windows-amd64.exe" .

# The Linux binary must be executable so a fresh clone can run it directly (git
# preserves the 100755 mode). Set it before moving into place. (No effect for the
# Windows .exe, which runs regardless of a POSIX exec bit.) When committing on a
# host whose filesystem doesn't carry the bit, stage it with
# `git update-index --chmod=+x prebuilt/bin/devkit-server-linux-amd64`.
chmod +x "$TMP_OUT/devkit-server-linux-amd64"

mkdir -p "$OUT_DIR"
mv "$TMP_OUT"/devkit-server-linux-amd64 "$TMP_OUT"/devkit-server-windows-amd64.exe "$OUT_DIR/"
echo "  → $OUT_DIR/devkit-server-linux-amd64"
echo "  → $OUT_DIR/devkit-server-windows-amd64.exe"

echo ""
echo "Build complete."
ls -lh "$OUT_DIR"/devkit-server-*
