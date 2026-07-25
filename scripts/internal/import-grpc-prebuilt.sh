#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/internal/import-grpc-prebuilt.sh
#
# Import the prebuilt gRPC packages into airgap-devkit's `prebuilt/` submodule,
# split into commit-friendly parts with a checksum manifest. This is the
# documented sync mechanism: the maintainer build is the source; airgap-devkit
# ships a frozen, checksummed copy so it stays independently releasable.
#
# Stages, per config in --configs (default: release):
#   * Windows MSVC packages for every toolset in --toolsets (v142/v143/v145),
#     as  grpc-<ver>-msvc<ts>-x64-<config>.zip  →  prebuilt/.../windows/<ver>/
#   * The Linux x86_64 release tarball (RHEL/Rocky 8/9/10), when present in --from,
#     as  grpc-<ver>-linux-x86_64.tar.gz         →  prebuilt/.../linux/<ver>/
#     (Linux ships Release only; it has no debug/release split.)
#
# USAGE:
#   bash scripts/internal/import-grpc-prebuilt.sh \
#       --from "$HOME/grpc-prebuilt/dist" \
#       [--version 1.83.0] [--toolsets 142,143,145] \
#       [--configs release,debug] [--part-size 45m] [--no-linux] [--prune-old]
#
# Requires: bash, split, sha256sum, python3 (all already devkit dependencies).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=scripts/internal/lib/devkit-prebuilt.sh
source "${SCRIPT_DIR}/lib/devkit-prebuilt.sh"

# ---------------------------------------------------------------------------
# Defaults / args
# ---------------------------------------------------------------------------
FROM_DIR="${GRPC_DIST_DIR:-$HOME/grpc-prebuilt/dist}"
VERSION="1.83.0"
TOOLSETS="142,143,145"
CONFIGS="release"
PART_SIZE="45m"
INCLUDE_LINUX=true
PRUNE_OLD=false

# VS-version labels per toolset (keep in sync with
# tools/frameworks/grpc/Check-Environment.ps1 and devkit.json variants).
_vs_version() {
    case "$1" in
        141) echo "Visual Studio 2017" ;;
        142) echo "Visual Studio 2019" ;;
        143) echo "Visual Studio 2022" ;;
        145) echo "Visual Studio 2026" ;;
        *)   echo "MSVC v$1" ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)      FROM_DIR="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --toolsets)  TOOLSETS="$2"; shift 2 ;;
        --configs)   CONFIGS="$2"; shift 2 ;;
        --part-size) PART_SIZE="$2"; shift 2 ;;
        --no-linux)  INCLUDE_LINUX=false; shift ;;
        --prune-old) PRUNE_OLD=true; shift ;;
        -h|--help)
            sed -n '2,30p' "$0"; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

WIN_DEST_DIR="${REPO_ROOT}/prebuilt/frameworks/grpc/windows/${VERSION}"
LINUX_DEST_DIR="${REPO_ROOT}/prebuilt/frameworks/grpc/linux/${VERSION}"

[[ -d "${FROM_DIR}" ]] || fail "Source dist dir not found: ${FROM_DIR}"
command -v sha256sum >/dev/null || fail "sha256sum is required"
command -v python3   >/dev/null || fail "python3 is required"

log "Importing gRPC ${VERSION} packages"
echo "    Source  : ${FROM_DIR}"
echo "    Win dest: ${WIN_DEST_DIR}"
echo "    Lnx dest: ${LINUX_DEST_DIR}"
echo "    Tools   : ${TOOLSETS}   Configs: ${CONFIGS}   (part size ${PART_SIZE})"

# ---------------------------------------------------------------------------
# Prune old version dirs (optional) — under both windows/ and linux/
# ---------------------------------------------------------------------------
if [[ "${PRUNE_OLD}" == true ]]; then
    for platform_dir in \
        "${REPO_ROOT}/prebuilt/frameworks/grpc/windows" \
        "${REPO_ROOT}/prebuilt/frameworks/grpc/linux"; do
        [[ -d "${platform_dir}" ]] || continue
        for d in "${platform_dir}"/*/; do
            base="$(basename "${d%/}")"
            [[ "${base}" == "${VERSION}" ]] && continue
            [[ "${base}" == "README.md" ]] && continue
            if [[ -d "${d}" ]]; then
                warn "Pruning old prebuilt dir: ${d}"
                rm -rf "${d}"
            fi
        done
    done
fi

# ---------------------------------------------------------------------------
# Windows: split each package into parts + record checksums
# ---------------------------------------------------------------------------
# Emits, per (toolset,config), a line: "<toolset>|<config>|<archive>|<full_sha256>"
# so the manifest builder can pair the parts (scanned from disk) with metadata.
mkdir -p "${WIN_DEST_DIR}"
META_FILE="$(mktemp)"
trap 'rm -f "${META_FILE}"' EXIT

IFS=',' read -r -a TS_ARR <<< "${TOOLSETS}"
IFS=',' read -r -a CFG_ARR <<< "${CONFIGS}"
for cfg in "${CFG_ARR[@]}"; do
    cfg="$(echo "$cfg" | tr -d '[:space:]')"
    for ts in "${TS_ARR[@]}"; do
        ts="$(echo "$ts" | tr -d '[:space:]')"
        archive="grpc-${VERSION}-msvc${ts}-x64-${cfg}.zip"
        src="${FROM_DIR}/${archive}"
        [[ -f "${src}" ]] || fail "Missing source package: ${src}"

        log "toolset v${ts}  ($(_vs_version "${ts}"))  ${cfg}  ->  ${archive}"
        full_sha="$(sha256 "${src}")"
        echo "    full sha256: ${full_sha}"

        # Remove any stale parts/whole archive for this package, then split fresh.
        rm -f "${WIN_DEST_DIR}/${archive}" "${WIN_DEST_DIR}/${archive}".part-*
        echo "    Splitting into ${PART_SIZE} parts (source left intact)..."
        split -b "${PART_SIZE}" --suffix-length=2 "${src}" "${WIN_DEST_DIR}/${archive}.part-"
        n_parts="$(ls "${WIN_DEST_DIR}/${archive}".part-* | wc -l | tr -d '[:space:]')"
        ok "${n_parts} part(s) written for ${archive}"

        echo "${ts}|${cfg}|${archive}|${full_sha}" >> "${META_FILE}"
    done
done

# ---------------------------------------------------------------------------
# Windows manifest.json (multi-variant: one platform key per toolset+config)
# ---------------------------------------------------------------------------
log "Writing Windows manifest.json"
python3 - "${WIN_DEST_DIR}" "${VERSION}" "${META_FILE}" <<'PY'
import hashlib, json, os, sys

dest_dir, version, meta_file = sys.argv[1], sys.argv[2], sys.argv[3]

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

VS = {"141": "Visual Studio 2017", "142": "Visual Studio 2019",
      "143": "Visual Studio 2022", "145": "Visual Studio 2026"}

rows = []
with open(meta_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        ts, cfg, archive, full = line.split("|")
        rows.append((ts, cfg, archive, full))

platforms, variants = {}, []
# Default preference: release before debug, then v143 (VS2022, mainstream) first.
ts_order = {"143": 0, "145": 1, "142": 2, "141": 3}
cfg_order = {"release": 0, "debug": 1}
rows.sort(key=lambda r: (cfg_order.get(r[1], 9), ts_order.get(r[0], 9)))

for i, (ts, cfg, archive, full) in enumerate(rows):
    parts = sorted(p for p in os.listdir(dest_dir)
                   if p.startswith(archive + ".part-"))
    part_sha = {p: sha256(os.path.join(dest_dir, p)) for p in parts}
    platforms[f"windows-msvc{ts}-{cfg}"] = {
        "archive": archive,
        "toolset": f"v{ts}",
        "config": cfg,
        "vs_version": VS.get(ts, f"MSVC v{ts}"),
        "sha256": full,
        "part_sha256": part_sha,
        "reassemble": f"cat {archive}.part-* > {archive} && unzip -o {archive}",
    }
    variants.append({
        "id": f"v{ts}-{cfg}",
        "toolset": f"v{ts}",
        "config": cfg,
        "vs_version": VS.get(ts, f"MSVC v{ts}"),
        "archive": archive,
        "default": i == 0,
    })

manifest = {
    "tool": "grpc",
    "version": version,
    "source": f"https://github.com/grpc/grpc/releases/tag/v{version}",
    "provenance": "grpc (maintainer prebuilt, per-toolset release+debug configuration)",
    "platforms": platforms,
    "compression": "zip",
    "part_size_mb": 45,
    "variants": variants,
}

with open(os.path.join(dest_dir, "manifest.json"), "w") as mf:
    json.dump(manifest, mf, indent=2)
    mf.write("\n")

print(f"  OK  Windows manifest.json  ({len(platforms)} package variant(s))")
PY

# ---------------------------------------------------------------------------
# Linux: split the RHEL/Rocky 8/9/10 x86_64 release tarball + its own manifest
# ---------------------------------------------------------------------------
LINUX_ARCHIVE="grpc-${VERSION}-linux-x86_64.tar.gz"
LINUX_SRC="${FROM_DIR}/${LINUX_ARCHIVE}"
if [[ "${INCLUDE_LINUX}" == true && -f "${LINUX_SRC}" ]]; then
    mkdir -p "${LINUX_DEST_DIR}"
    log "linux x86_64 (RHEL/Rocky 8/9/10)  ->  ${LINUX_ARCHIVE}"
    linux_full_sha="$(sha256 "${LINUX_SRC}")"
    echo "    full sha256: ${linux_full_sha}"

    rm -f "${LINUX_DEST_DIR}/${LINUX_ARCHIVE}" "${LINUX_DEST_DIR}/${LINUX_ARCHIVE}".part-*
    echo "    Splitting into ${PART_SIZE} parts (source left intact)..."
    split -b "${PART_SIZE}" --suffix-length=2 "${LINUX_SRC}" "${LINUX_DEST_DIR}/${LINUX_ARCHIVE}.part-"
    n_parts="$(ls "${LINUX_DEST_DIR}/${LINUX_ARCHIVE}".part-* | wc -l | tr -d '[:space:]')"
    ok "${n_parts} part(s) written for ${LINUX_ARCHIVE}"

    log "Writing Linux manifest.json"
    python3 - "${LINUX_DEST_DIR}" "${VERSION}" "${LINUX_ARCHIVE}" "${linux_full_sha}" <<'PY'
import hashlib, json, os, sys
dest_dir, version, archive, full = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

parts = sorted(p for p in os.listdir(dest_dir) if p.startswith(archive + ".part-"))
part_sha = {p: sha256(os.path.join(dest_dir, p)) for p in parts}

manifest = {
    "tool": "grpc",
    "version": version,
    "source": f"https://github.com/grpc/grpc/releases/tag/v{version}",
    "provenance": "grpc (maintainer prebuilt, RHEL/Rocky 8/9/10 gcc-toolset release, static libstdc++)",
    "platforms": {
        "linux-x86_64": {
            "archive": archive,
            "config": "release",
            "sha256": full,
            "part_sha256": part_sha,
            "reassemble": f"cat {archive}.part-* > {archive} && tar xzf {archive}",
        }
    },
    "compression": "tar.gz",
    "part_size_mb": 45,
    "variants": [
        {"id": "linux", "archive": archive, "config": "release", "default": True}
    ],
}

with open(os.path.join(dest_dir, "manifest.json"), "w") as mf:
    json.dump(manifest, mf, indent=2)
    mf.write("\n")

print("  OK  Linux manifest.json  (1 package variant)")
PY
elif [[ "${INCLUDE_LINUX}" == true ]]; then
    warn "Linux tarball not found (${LINUX_SRC}); skipping Linux import."
fi

ok "gRPC ${VERSION} imported"
echo ""
echo "    Next: review the parts + manifests, then commit inside the prebuilt"
echo "    submodule and bump its pointer in the main repo."
