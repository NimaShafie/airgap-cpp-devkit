#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/generate-sbom.sh
#
# PURPOSE: Regenerate all SPDX 2.3 SBOM files for airgap-cpp-devkit.
#          Updates the creationInfo.created timestamp in every SBOM to now.
#          All other content (versions, hashes, licenses) is static and must
#          be updated manually when vendored components change.
#
# USAGE:
#   bash scripts/generate-sbom.sh
#
# OUTPUT:
#   sbom.spdx.json                                    <- root aggregate
#   clang-llvm-source-build/sbom.spdx.json
#   clang-llvm-style-formatter/sbom.spdx.json
#   git-bundle/sbom.spdx.json
#   prebuilt/winlibs-gcc-ucrt/sbom.spdx.json
#
# VALIDATION:
#   Submit any output file to https://tools.spdx.org/app/validate/
#   to confirm SPDX 2.3 conformance before submitting for corporate approval.
#
# MAINTENANCE:
#   When a vendored component version changes:
#     1. Update the relevant subproject sbom.spdx.json manually
#     2. Update the root sbom.spdx.json comment for that subproject
#     3. Re-run this script to refresh timestamps
#     4. Commit all sbom.spdx.json files together with the version bump
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "============================================================"
echo " airgap-cpp-devkit — SBOM Generator"
echo " Timestamp: ${TIMESTAMP}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Helper: update the created timestamp in an existing SBOM file in-place
# ---------------------------------------------------------------------------
update_timestamp() {
  local sbom_file="$1"
  if [[ ! -f "${sbom_file}" ]]; then
    echo "[WARN] Not found, skipping timestamp update: ${sbom_file}" >&2
    return
  fi
  # Replace the created field value using sed
  sed -i "s/\"created\": \"[0-9T:Z-]*\"/\"created\": \"${TIMESTAMP}\"/" "${sbom_file}"
  echo "[OK] Updated timestamp: ${sbom_file}"
}

# ---------------------------------------------------------------------------
# Update timestamps in all SBOM files
# ---------------------------------------------------------------------------
update_timestamp "${REPO_ROOT}/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/clang-llvm-source-build/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/clang-llvm-style-formatter/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/git-bundle/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/prebuilt/winlibs-gcc-ucrt/sbom.spdx.json"

echo ""

# ---------------------------------------------------------------------------
# Verify all files exist and are valid JSON
# ---------------------------------------------------------------------------
echo "Verifying JSON syntax..."
ALL_OK=true
for sbom in \
  "${REPO_ROOT}/sbom.spdx.json" \
  "${REPO_ROOT}/clang-llvm-source-build/sbom.spdx.json" \
  "${REPO_ROOT}/clang-llvm-style-formatter/sbom.spdx.json" \
  "${REPO_ROOT}/git-bundle/sbom.spdx.json" \
  "${REPO_ROOT}/prebuilt/winlibs-gcc-ucrt/sbom.spdx.json"
do
  if [[ ! -f "${sbom}" ]]; then
    echo "  [FAIL] Missing: ${sbom}" >&2
    ALL_OK=false
    continue
  fi
  # Validate JSON using Python (available on all target platforms)
  if python3 -c "import json,sys; json.load(open('${sbom}'))" 2>/dev/null; then
    echo "  [PASS] ${sbom#${REPO_ROOT}/}"
  else
    echo "  [FAIL] Invalid JSON: ${sbom}" >&2
    ALL_OK=false
  fi
done

echo ""

if [[ "${ALL_OK}" == "true" ]]; then
  echo "============================================================"
  echo " [SUCCESS] All SBOM files updated and valid."
  echo ""
  echo " Files:"
  echo "   sbom.spdx.json                              (root)"
  echo "   clang-llvm-source-build/sbom.spdx.json"
  echo "   clang-llvm-style-formatter/sbom.spdx.json"
  echo "   git-bundle/sbom.spdx.json"
  echo "   prebuilt/winlibs-gcc-ucrt/sbom.spdx.json"
  echo ""
  echo " Validate online: https://tools.spdx.org/app/validate/"
  echo "============================================================"
else
  echo "[FAIL] One or more SBOM files have issues." >&2
  exit 1
fi