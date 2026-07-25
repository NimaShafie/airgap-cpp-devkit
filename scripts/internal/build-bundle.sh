#!/usr/bin/env bash
# scripts/internal/build-bundle.sh
# ─────────────────────────────────────────────────────────────────────────────
# Build a single, self-contained OFFLINE bundle for one platform: a mini-repo
# containing the install scripts, tool definitions, prebuilt manifests, and the
# platform's binary artifacts. An operator unpacks it with OS-native tools (no
# admin, no 7-Zip/xz) and transfers it to the fully air-gapped host, where the
# normal installer runs against it with zero network access.
#
# Outer container is itself native/no-admin:
#   Windows → airgap-devkit-<version>-windows.zip     (Explorer / Expand-Archive)
#   Linux   → airgap-devkit-<version>-linux.tar.gz    (base tar)
#
# Binary artifacts are taken from either:
#   • a reachable mirror  — set DEVKIT_ARTIFACT_BASE and pass --fetch (rehydrates
#     via fetch-artifacts.sh, SHA256-verified), or
#   • the local ./prebuilt tree (default) — used as-is (already SHA256-checked by
#     the installer at install time).
#
# Usage:
#   bash scripts/internal/build-bundle.sh --platform windows|linux
#       [--version X.Y.Z] [--artifacts <dir>] [--out <dir>] [--fetch]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/devkit-prebuilt.sh"

PLATFORM=""
VERSION=""
ARTIFACTS="$REPO_ROOT/prebuilt"
OUT="$REPO_ROOT/dist/bundles"
DO_FETCH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)  PLATFORM="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --artifacts) ARTIFACTS="$2"; shift 2 ;;
        --out)       OUT="$2"; shift 2 ;;
        --fetch)     DO_FETCH=true; shift ;;
        -h|--help)   sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           fail "Unknown argument: $1" ;;
    esac
done

case "$PLATFORM" in
    windows|linux) ;;
    *) fail "--platform must be windows or linux" ;;
esac

# Version defaults to the AppVersion baked into the Go server.
if [[ -z "$VERSION" ]]; then
    VERSION="$(grep -oE 'AppVersion[[:space:]]*=[[:space:]]*"[^"]+"' \
        "$REPO_ROOT/server/internal/api/version.go" 2>/dev/null \
        | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
    [[ -z "$VERSION" ]] && fail "Could not detect version; pass --version X.Y.Z"
fi

command -v python3 >/dev/null 2>&1 || fail "python3 is required"

BUNDLE_NAME="airgap-devkit-${VERSION}-${PLATFORM}"
STAGE="$OUT/$BUNDLE_NAME"

log "Building bundle : $BUNDLE_NAME"
log "Artifacts from  : $ARTIFACTS"
log "Output dir      : $OUT"

rm -rf "$STAGE"
mkdir -p "$STAGE/prebuilt"

# 1. Install scripts + tool definitions (the "how to install" half of the repo).
log "Copying install scripts and tool definitions"
cp -r "$REPO_ROOT/tools"   "$STAGE/tools"
cp -r "$REPO_ROOT/scripts" "$STAGE/scripts"
for extra in devkit.config.json README.md LICENSE tests; do
    [[ -e "$REPO_ROOT/$extra" ]] && cp -r "$REPO_ROOT/$extra" "$STAGE/$extra"
done

# 2. Prebuilt manifests (always) + this platform's binary artifacts.
log "Assembling prebuilt manifests + ${PLATFORM} artifacts"

if [[ "$DO_FETCH" == true ]]; then
    # Rehydrate exactly this platform's artifacts from the configured mirror.
    # Manifests must already be present in $ARTIFACTS to drive the fetch.
    find "$ARTIFACTS" -name manifest.json -type f | while IFS= read -r m; do
        rel="${m#$ARTIFACTS/}"; mkdir -p "$STAGE/prebuilt/$(dirname "$rel")"
        cp "$m" "$STAGE/prebuilt/$rel"
    done
    bash "$SCRIPT_DIR/fetch-artifacts.sh" --platform "$PLATFORM" \
        --manifests "$STAGE/prebuilt" --dest "$STAGE/prebuilt"
else
    # Copy manifests + the platform's enumerated files straight from local prebuilt.
    while IFS= read -r manifest; do
        reldir="$(dirname "${manifest#$ARTIFACTS/}")"
        mkdir -p "$STAGE/prebuilt/$reldir"
        cp "$manifest" "$STAGE/prebuilt/$reldir/manifest.json"
        while IFS=$'\t' read -r name _sha; do
            [[ -z "$name" ]] && continue
            src="$ARTIFACTS/$reldir/$name"
            if [[ -f "$src" ]]; then
                cp "$src" "$STAGE/prebuilt/$reldir/$name"
            else
                warn "missing artifact (skipped): $reldir/$name"
            fi
        done < <(python3 "$SCRIPT_DIR/lib/enumerate-artifacts.py" "$manifest" "$PLATFORM" | tr -d '\r')
    done < <(find "$ARTIFACTS" -name manifest.json -type f | sort)
fi

# 3. Offline install pointer.
cat > "$STAGE/INSTALL-OFFLINE.txt" << TXT
airgap-cpp-devkit — offline bundle ${VERSION} (${PLATFORM})

This bundle is fully self-contained. No network access is required to install.

Windows:
  1. Right-click the .zip → "Extract All" (or: Expand-Archive in PowerShell).
  2. Open Git Bash in the extracted ${BUNDLE_NAME}\\ folder.
  3. bash scripts/internal/install-cli.sh --yes --profile cpp-dev

Linux (RHEL/Rocky 8, 9, 10):
  1. tar -xzf ${BUNDLE_NAME}.tar.gz
  2. cd ${BUNDLE_NAME}
  3. bash scripts/internal/install-cli.sh --yes --profile cpp-dev

All tools install into your user profile — no administrator rights needed.
Every archive is verified against its manifest SHA256 during install.
TXT

# 4. Native outer container.
mkdir -p "$OUT"
if [[ "$PLATFORM" == "windows" ]]; then
    OUTFILE="$OUT/${BUNDLE_NAME}.zip"
    log "Packing → $(basename "$OUTFILE")"
    rm -f "$OUTFILE"
    if command -v zip &>/dev/null; then
        ( cd "$OUT" && zip -qr "$OUTFILE" "$BUNDLE_NAME" )
    elif command -v 7za &>/dev/null; then
        ( cd "$OUT" && 7za a -tzip -bso0 -bsp0 "$OUTFILE" "$BUNDLE_NAME" >/dev/null )
    else
        ( cd "$OUT" && python3 - "$OUTFILE" "$BUNDLE_NAME" <<'PY'
import os, sys, zipfile
out, top = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dp, _, fs in os.walk(top):
        for f in fs:
            full = os.path.join(dp, f)
            z.write(full, full)
PY
        )
    fi
else
    OUTFILE="$OUT/${BUNDLE_NAME}.tar.gz"
    log "Packing → $(basename "$OUTFILE")"
    tar -czf "$OUTFILE" -C "$OUT" "$BUNDLE_NAME"
fi

SHA="$(sha256 "$OUTFILE")"
echo "$SHA  $(basename "$OUTFILE")" > "$OUTFILE.sha256"

echo ""
echo "============================================================"
echo " Bundle: $OUTFILE"
echo " SHA256: $SHA"
echo " Transfer this single file to the air-gapped host and follow"
echo " INSTALL-OFFLINE.txt inside it."
echo "============================================================"
