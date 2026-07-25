#!/usr/bin/env bash
# scripts/internal/restage-local.sh
# ─────────────────────────────────────────────────────────────────────────────
# Convert ALREADY-STAGED prebuilt archives (.tar.xz / .7z, whole or split) into
# the native, no-admin format (.zip on Windows, .tar.gz on Linux) — OFFLINE and
# IN PLACE. No internet, no version changes: the exact same binaries are simply
# repackaged, payload normalized to the archive root, and manifests regenerated.
#
# Installers (.exe/.msi) and packages (.rpm/.deb) and already-native archives
# (.zip/.tar.gz) are left untouched.
#
# Usage:
#   bash scripts/internal/restage-local.sh --all                 # whole prebuilt tree
#   bash scripts/internal/restage-local.sh [--dest <dir>] <version-dir>...
#
#   --dest <dir>  Write converted output under <dir> instead of in place (the
#                 source tree is left untouched — used for validation).
#   --all         Process every manifest dir under prebuilt/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
source "$SCRIPT_DIR/lib/devkit-prebuilt.sh"
GENMANIFEST="$SCRIPT_DIR/lib/generate-manifest.py"
PREBUILT="$REPO_ROOT/prebuilt"

DEST=""
ALL=false
DIRS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest) DEST="$2"; shift 2 ;;
        --all)  ALL=true; shift ;;
        *)      DIRS+=("$1"); shift ;;
    esac
done

$ALL && while IFS= read -r m; do DIRS+=("$(dirname "$m")"); done \
    < <(find "$PREBUILT" -name manifest.json -type f | sort)
[[ ${#DIRS[@]} -eq 0 ]] && fail "No version dirs given (use --all or pass dirs containing manifest.json)."

command -v python3 >/dev/null 2>&1 || fail "python3 is required"

# A POSIX/Linux archive (→ .tar.gz, transcoded to preserve symlinks). Recognize
# distro/host tags beyond bare "linux" (e.g. llvm-mingw ships an *ubuntu* build).
is_linux_name() {
    local n="${1,,}"
    [[ "$n" == *linux*  || "$n" == *ubuntu* || "$n" == *debian* || "$n" == *rhel* \
    || "$n" == *el8*    || "$n" == *el9*    || "$n" == *el10*   || "$n" == *musl* \
    || "$n" == *-gnu*   || "$n" == *.rpm    || "$n" == *.deb ]]
}

process_dir() {
    local src_dir="$1"
    local rel="${src_dir#$PREBUILT/}"
    local out_dir="$src_dir"
    if [[ -n "$DEST" ]]; then
        out_dir="$DEST/$rel"
        mkdir -p "$out_dir"
        # Copy through everything; converted archives overwrite their .tar.xz/.7z originals below.
        cp -rf "$src_dir/." "$out_dir/"
    fi

    log "Converting: $rel"

    # Collect archive bases to convert: whole .tar.xz/.7z and split .part-aa sets.
    local -A bases=()
    while IFS= read -r f; do
        local b; b="$(basename "$f")"
        case "$b" in
            *.part-aa) bases["${b%.part-aa}"]="split" ;;
            *.tar.xz|*.7z) [[ "$b" == *.part-* ]] || bases["$b"]="whole" ;;
        esac
    done < <(find "$src_dir" -maxdepth 1 -type f \( -name '*.tar.xz' -o -name '*.7z' -o -name '*.tar.xz.part-aa' -o -name '*.7z.part-aa' \))

    local base kind
    for base in "${!bases[@]}"; do
        kind="${bases[$base]}"
        local whole="$TMP_DIR/$base"
        if [[ "$kind" == split ]]; then
            cat "$src_dir/$base.part-"* > "$whole"
        else
            cp "$src_dir/$base" "$whole"
        fi

        # Target native name.
        local stem ext target
        case "$base" in
            *.tar.xz) stem="${base%.tar.xz}" ;;
            *.7z)     stem="${base%.7z}" ;;
        esac
        if is_linux_name "$base"; then ext="tar.gz"; else ext="zip"; fi
        target="$out_dir/$stem.$ext"

        if [[ "$ext" == "tar.gz" ]]; then
            # Linux: transcode the stream (no extraction) so symlinks/layout survive.
            devkit_transcode_targz "$whole" "$target"
        else
            # Windows: extract→zip, auto-normalizing a sole wrapper dir (zip cannot
            # strip on extract, and Windows payloads have no symlink concern).
            devkit_repack "$whole" "$target" auto
        fi

        # Split the native archive if it exceeds 50MB (matches prebuilt convention).
        local sz; sz=$(wc -c < "$target")
        if (( sz > 50 * 1024 * 1024 )); then
            split_parts "$target" "$out_dir" "$(basename "$target")"
        fi

        # Remove the legacy source(s) from the output dir.
        if [[ "$kind" == split ]]; then rm -f "$out_dir/$base.part-"*; else rm -f "$out_dir/$base"; fi
        rm -f "$whole"
        ok "→ $(basename "$target")"
    done

    # Regenerate the manifest from whatever now sits in the output dir.
    local tool version
    tool=$(json_field "$out_dir/manifest.json" "tool")
    version=$(json_field "$out_dir/manifest.json" "version")
    [[ -z "$tool" ]] && tool="$(basename "$(dirname "$out_dir")")"
    [[ -z "$version" ]] && version="$(basename "$out_dir")"
    python3 "$GENMANIFEST" "$out_dir" "$tool" "$version" "" ""
}

for d in "${DIRS[@]}"; do
    [[ -f "$d/manifest.json" ]] || { warn "skip (no manifest.json): $d"; continue; }
    process_dir "$d"
done

echo ""
echo "Done. Verify with: bash scripts/internal/check-formats.sh"
