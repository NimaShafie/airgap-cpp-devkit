#!/usr/bin/env bash
# Starts the devkit server binary, verifies three API endpoints, then stops it.
# Required env: DEVKIT_BINARY (path to the platform binary)
set -euo pipefail

: "${DEVKIT_BINARY:?DEVKIT_BINARY must be set to the server binary path}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Use a non-default port: :9090 collides with Cockpit on RHEL/Rocky, which would
# make the server fail to bind and the smoke test flap for reasons unrelated to
# the build.
PORT="${SMOKE_PORT:-9191}"
BASE="http://127.0.0.1:${PORT}"

# The committed Linux binary is mode 100755, so no runtime chmod is needed — and
# chmod-ing it here would dirty the prebuilt submodule if the mode ever regressed.

# Release gate: the committed binary MUST match the source version. This is the
# check that would have caught shipping a stale binary. Parse the AppVersion
# literal from source and assert the binary's --version ends with it.
APP_VERSION="$(grep -oE 'AppVersion = "[^"]+"' server/internal/api/version.go | grep -oE '"[^"]+"' | tr -d '"')"
[[ -n "$APP_VERSION" ]] || { echo "ERROR: could not parse AppVersion from version.go" >&2; exit 1; }
BIN_VERSION_LINE="$("$DEVKIT_BINARY" --version 2>&1 || true)"
echo "AppVersion (source): $APP_VERSION"
echo "Binary --version   : $BIN_VERSION_LINE"
case "$BIN_VERSION_LINE" in
  *"$APP_VERSION") echo "Version match: OK" ;;
  *) echo "ERROR: binary --version ('$BIN_VERSION_LINE') != source AppVersion ('$APP_VERSION')." >&2
     echo "       The committed binary is stale — rebuild via scripts/internal/build-server.sh." >&2
     exit 1 ;;
esac

echo '{"setup_complete": true}' > devkit.config.json

"$DEVKIT_BINARY" --tools tools --prebuilt prebuilt --port "$PORT" --no-browser &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; rm -f devkit.config.json' EXIT

for i in $(seq 1 15); do
  curl -sf "$BASE/health" && echo "Server ready." && break
  [[ $i -eq 15 ]] && { echo "ERROR: server did not become ready" >&2; exit 1; }
  sleep 1
done

TOKEN=$(cat .devkit-token 2>/dev/null || echo "")

curl -sf "$BASE/health"

resp=$(curl -sf -H "X-DevKit-Token: $TOKEN" "$BASE/api/tools")
count=$(python3 -c "import json,sys; print(len(json.load(sys.stdin)))" <<< "$resp")
echo "Discovered $count tools"
[[ "$count" -gt 0 ]] || { echo "ERROR: /api/tools returned no tools" >&2; exit 1; }

curl -sf -H "X-DevKit-Token: $TOKEN" "$BASE/api/profiles"
echo "Smoke test passed."
