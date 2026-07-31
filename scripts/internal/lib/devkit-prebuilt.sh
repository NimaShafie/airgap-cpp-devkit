#!/usr/bin/env bash
# scripts/internal/lib/devkit-prebuilt.sh
# Shared helpers for airgap-devkit prebuilt management scripts.
# Source this file; do not execute directly.
# Compatible with: Git Bash (MINGW64) on Windows, Bash 4.x on RHEL/Rocky 8/9/10 / Linux.

[[ -n "${_DEVKIT_PREBUILT_SH:-}" ]] && return 0
_DEVKIT_PREBUILT_SH=1

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    [OK] %s\n' "$*"; }
warn() { printf '    [WARN] %s\n' "$*" >&2; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# Download with curl; skip if already present.
dl() {
    local url="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        ok "Already present: $(basename "$dest")"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    echo "    Downloading $(basename "$dest")..."
    curl -fL --progress-bar -o "$dest" "$url" \
        || fail "Download failed: $url"
}

# Compute SHA256 of a file.
sha256() { sha256sum "$1" | awk '{print $1}'; }

# Canonical staged formats are the ones a bare, no-admin target can extract with
# OS-native tooling: .zip on Windows (Explorer / Expand-Archive) and .tar.gz on
# Linux (base tar). We never stage .tar.xz or .7z — those need extra unpackers.

# devkit_platform_ext PLATFORM → echo the canonical archive extension.
#   windows → zip     linux (anything else) → tar.gz
devkit_platform_ext() {
    [[ "$1" == "windows" ]] && echo "zip" || echo "tar.gz"
}

# _devkit_zip_dir SRC_ROOT DEST_ZIP
# Create DEST_ZIP from the CONTENTS of SRC_ROOT (flat — no wrapper directory).
# Prefers `zip`, then `7za`, then python3's zipfile (always available since
# python3 is already a hard dependency of the staging scripts).
_devkit_zip_dir() {
    local root="$1" dest="$2"
    dest="$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"   # absolutize
    rm -f "$dest"
    if command -v zip &>/dev/null; then
        ( cd "$root" && zip -qr "$dest" . )
    elif command -v 7za &>/dev/null; then
        ( cd "$root" && 7za a -tzip -bso0 -bsp0 "$dest" . >/dev/null )
    else
        ( cd "$root" && python3 - "$dest" <<'PY'
import os, sys, zipfile
dest = sys.argv[1]
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, _, files in os.walk("."):
        for f in files:
            full = os.path.join(dirpath, f)
            z.write(full, os.path.relpath(full, "."))
PY
        )
    fi
    [[ -f "$dest" ]] || fail "zip creation failed: $dest"
}

# devkit_make_archive SRC_ROOT DEST
# Archive the CONTENTS of SRC_ROOT into DEST; the DEST extension picks the format
# (.zip → zip, .tar.gz → gzip). Contents land at the archive root (no wrapper).
devkit_make_archive() {
    local root="$1" dest="$2"
    case "$dest" in
        *.zip)     _devkit_zip_dir "$root" "$dest" ;;
        *.tar.gz)  tar -czf "$dest" -C "$root" . ;;
        *)         fail "devkit_make_archive: unsupported dest format: $dest" ;;
    esac
}

# devkit_transcode_targz SRC DEST
# Convert a Linux tar archive (.tar.xz/.tar.gz/.tgz) to .tar.gz WITHOUT extracting
# it — the tar payload is preserved byte-for-byte, so POSIX symlinks and the
# internal directory layout survive intact. This is mandatory on Windows/MSYS,
# where extracting a Linux tarball cannot recreate symlinks (they become copies
# or hard-fail). Because nothing is extracted, the wrapper dir is NOT stripped;
# the install side strips to match the archive's existing layout.
devkit_transcode_targz() {
    local src="$1" dest="$2"
    case "$src" in
        *.tar.gz|*.tgz)
            # Source is already native .tar.gz; if it resolves to the same file
            # as the destination there is nothing to transcode.
            [[ "$src" -ef "$dest" ]] || cp -f "$src" "$dest" ;;
        *.tar.xz)
            if command -v xz &>/dev/null; then
                xz -dc "$src" | gzip -nc > "$dest"
            else
                # Portable fallback: stream xz→gz via Python stdlib (no extraction).
                python3 - "$src" "$dest" <<'PY'
import lzma, gzip, shutil, sys
with lzma.open(sys.argv[1], "rb") as fi, gzip.open(sys.argv[2], "wb", 6) as fo:
    shutil.copyfileobj(fi, fo, 1024 * 1024)
PY
            fi ;;
        *) fail "devkit_transcode_targz: unsupported source: $src" ;;
    esac
    [[ -s "$dest" ]] || fail "devkit_transcode_targz: produced empty file: $dest"
}

# devkit_repack SRC DEST [auto|strip1|flat]
# Extract SRC (.zip/.tar.gz/.tgz/.tar.xz/.7z) and repackage into DEST (.zip/.tar.gz).
#   auto   — strip a single top-level wrapper DIRECTORY if (and only if) that is
#            the sole root entry; otherwise keep contents flat (default). This is
#            correct whether the payload is wrapped (cmake-4.3.3-*/) or is a bare
#            file at the root (e.g. ninja).
#   strip1 — force-strip the single top-level wrapper dir (no-op if it is a file).
#   flat   — always keep contents at the root as-is.
devkit_repack() {
    local src="$1" dest="$2" mode="${3:-auto}"
    local tmp; tmp="$(mktemp -d -p "${TMP_DIR:-/tmp}")"
    echo "    Extracting $(basename "$src")..."
    mkdir -p "$tmp/raw"
    case "$src" in
        *.zip)           unzip -q "$src" -d "$tmp/raw" ;;
        *.tar.gz|*.tgz)  tar -xzf "$src" -C "$tmp/raw" ;;
        *.tar.xz)        tar -xJf "$src" -C "$tmp/raw" ;;
        *.7z)
            command -v 7za &>/dev/null || command -v 7z &>/dev/null \
                || fail "devkit_repack: 7za/7z required to unpack $src"
            local sz; sz="$(command -v 7za || command -v 7z)"
            "$sz" x -y -o"$tmp/raw" "$src" >/dev/null ;;
        *)               fail "devkit_repack: unsupported source format: $src" ;;
    esac

    # Decide the archive root. Only strip a wrapper when the sole top-level entry
    # is a directory — never when it is a single file.
    local root="$tmp/raw"
    local entries=("$tmp"/raw/*)
    case "$mode" in
        auto|strip1)
            if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
                root="${entries[0]}"
            fi
            ;;
        flat) ;;
        *) fail "devkit_repack: unknown mode: $mode" ;;
    esac

    echo "    Repackaging → $(basename "$dest")..."
    devkit_make_archive "$root" "$dest"
    rm -rf "$tmp"
}

# Split a file into parts and delete the source.
# Uses alphabetic suffixes (part-aa, part-ab, ...) matching the existing prebuilt convention.
# Never use -d (numeric suffixes) — it breaks cat *.part-* glob ordering.
split_parts() {
    local src="$1" dir="$2" basename="$3"
    local part_size="${PART_SIZE:-50m}"
    echo "    Splitting into ${part_size} parts..."
    split -b "$part_size" --suffix-length=2 "$src" "$dir/${basename}.part-"
    rm -f "$src"
    ok "Parts written: $dir/${basename}.part-*"
}

# Extract a single string field from a JSON file using python3.
# Returns empty string if the key is absent or its value is null.
json_field() {
    local file="$1" key="$2"
    python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2])
    print('' if v is None else str(v))
except Exception:
    print('')
" "$file" "$key"
}
