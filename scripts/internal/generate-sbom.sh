#!/usr/bin/env bash
# =============================================================================
# scripts/internal/generate-sbom.sh
#
# PURPOSE: Regenerate the SPDX 2.3 root SBOM for airgap-cpp-devkit.
#          - Refreshes the creationInfo.created timestamp.
#          - Embeds real SHA-256 checksums for each package, read from the
#            per-tool prebuilt manifests (prebuilt/**/manifest.json), and syncs
#            each package's versionInfo to the newest prebuilt version.
#          - The SBOM is self-contained: it does not reference external
#            per-tool sub-SBOM documents.
#
# USAGE:
#   bash scripts/internal/generate-sbom.sh [--strict]
#
#   --strict : exit non-zero if any package that has prebuilt manifests could
#              not be resolved to a checksum (for CI gating).
# =============================================================================

set -euo pipefail

STRICT=false
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "============================================================"
echo " airgap-cpp-devkit -- SBOM Generator"
echo " Timestamp: ${TIMESTAMP}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Regenerate the root SBOM: refresh timestamp, drop external sub-SBOM refs, and
# embed real SHA-256 checksums for every package from the prebuilt manifests.
# ---------------------------------------------------------------------------
ROOT_SBOM="${REPO_ROOT}/sbom.spdx.json"
echo "Embedding SHA-256 checksums from prebuilt manifests..."

set +e
python3 - "${ROOT_SBOM}" "${REPO_ROOT}/prebuilt" "${TIMESTAMP}" << 'PYEOF'
import json, sys, re
from pathlib import Path
from collections import defaultdict

root_sbom, prebuilt, timestamp = sys.argv[1], Path(sys.argv[2]), sys.argv[3]

def vkey(v):
    """Sortable version key from any version string (e.g. '4.3.3', '20260407')."""
    nums = re.findall(r"\d+", str(v))
    return tuple(int(n) for n in nums) if nums else (0,)

# Index every prebuilt manifest once.
manifests = []
for mf in sorted(prebuilt.rglob("manifest.json")):
    try:
        d = json.load(open(mf))
    except Exception as e:
        print(f"[WARN] unreadable manifest {mf}: {e}")
        continue
    manifests.append((mf.parent.relative_to(prebuilt).parts, d))

def candidates(pkg_name):
    """Manifests whose prebuilt path is under the package's category/tool path."""
    n = tuple(pkg_name.split("/"))
    return [d for parts, d in manifests if parts[:len(n)] == n]

def newest_per_tool(cands):
    """Group candidate manifests by their `tool` field; keep the newest version of
    each. (Different tool identities under one path — e.g. gcc's winlibs vs
    gcc-toolset — are complementary and all kept; older versions collapse.) When a
    tool ships several manifests at the SAME newest version — e.g. gRPC's Windows
    and Linux platform manifests — keep all of them so every artifact is listed."""
    groups = defaultdict(list)
    for d in cands:
        groups[d.get("tool", "?")].append(d)
    picked = []
    for _, lst in groups.items():
        newest = max(vkey(d.get("version", "")) for d in lst)
        picked.extend(d for d in lst if vkey(d.get("version", "")) == newest)
    return picked

def collect(man):
    """Yield (label, filename, sha256) for every checksum in a manifest,
    across all the shapes prebuilt manifests use."""
    out = []
    plats = man.get("platforms", {})
    if not isinstance(plats, dict):
        return out
    for pk, pv in plats.items():
        if not isinstance(pv, dict):
            continue
        for key, val in pv.items():
            if key == "sha256" and isinstance(val, str):
                fn = pv.get("archive") or pv.get("binary") or pv.get("installer") or pk
                out.append((pk, fn, val))
            elif key == "part_sha256" and isinstance(val, dict):
                for part, h in val.items():
                    if isinstance(h, str):
                        out.append((pk, part, h))
            elif key.endswith("_sha256") and isinstance(val, str):
                prefix = key[: -len("_sha256")]
                fn = pv.get(prefix) or pv.get(prefix + "_archive") or f"{pk}-{prefix}"
                out.append((f"{pk}-{prefix}", fn, val))
    return out

doc = json.load(open(root_sbom))
doc.setdefault("creationInfo", {})["created"] = timestamp
doc["creationInfo"]["comment"] = (
    "Self-contained root SBOM for airgap-cpp-devkit. Package checksums are the "
    "SHA-256 of the prebuilt artifacts under prebuilt/."
)
# Remove the external sub-SBOM references (documents that are not shipped).
doc.pop("externalDocumentRefs", None)

resolved = unresolved = sourceless = 0
for pkg in doc.get("packages", []):
    name = pkg.get("name", "")
    picked = newest_per_tool(candidates(name))
    if not picked:
        sourceless += 1
        continue
    checks, attrs, seen, vers = [], [], set(), []
    for man in picked:
        vers.append(man.get("version", ""))
        for label, fn, h in collect(man):
            hl = h.lower()
            if set(hl) <= {"0"} or not re.fullmatch(r"[0-9a-f]{64}", hl):
                continue
            attrs.append(f"{label}: {fn} SHA256:{hl}")
            if hl not in seen:
                seen.add(hl)
                checks.append({"algorithm": "SHA256", "checksumValue": hl})
    if checks:
        if vers:
            pkg["versionInfo"] = max(vers, key=vkey)
        pkg["checksums"] = checks
        pkg["attributionTexts"] = attrs
        resolved += 1
        print(f"  [OK] {name:32} v{pkg['versionInfo']:12} {len(checks)} checksum(s)")
    else:
        unresolved += 1
        print(f"  [!!] {name:32} has manifests but no usable checksum")

with open(root_sbom, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")

print(f"\n[OK] {resolved} package(s) with embedded checksums, "
      f"{sourceless} without prebuilt artifacts, {unresolved} unresolved.")
sys.exit(2 if unresolved else 0)
PYEOF
SBOM_RC=$?
set -e

if [[ "${SBOM_RC}" -eq 2 ]]; then
  if [[ "${STRICT}" == "true" ]]; then
    echo "[FAIL] --strict: some packages with prebuilt manifests have no checksum." >&2
    exit 1
  fi
  echo "[WARN] Some packages with prebuilt manifests could not be resolved to a checksum." >&2
elif [[ "${SBOM_RC}" -ne 0 ]]; then
  echo "[FAIL] SBOM regeneration failed (rc=${SBOM_RC})." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Verify all files exist and are valid JSON
# ---------------------------------------------------------------------------
echo "Verifying JSON syntax..."
ALL_OK=true
sbom="${REPO_ROOT}/sbom.spdx.json"
if [[ ! -f "${sbom}" ]]; then
  echo "  [FAIL] Missing: ${sbom}" >&2
  ALL_OK=false
elif python3 -m json.tool "${sbom}" > /dev/null 2>&1; then
  echo "  [PASS] ${sbom#"${REPO_ROOT}"/}"
else
  echo "  [FAIL] Invalid JSON: ${sbom}" >&2
  ALL_OK=false
fi

echo ""

if [[ "${ALL_OK}" == "true" ]]; then
  echo "============================================================"
  echo " [SUCCESS] All SBOM files updated and valid."
  echo ""
  echo " File:"
  echo "   sbom.spdx.json   (self-contained; per-package SHA-256 embedded)"
  echo ""
  echo " Validate online: https://tools.spdx.org/app/validate/"
  echo "============================================================"
else
  echo "[FAIL] One or more SBOM files have issues." >&2
  exit 1
fi