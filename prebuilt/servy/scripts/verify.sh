#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# prebuilt/servy/scripts/verify.sh
#
# Verifies SHA256 checksums of all vendored Servy split parts.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/servy"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

fail=0

verify_file() {
  local filepath="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -f "${filepath}" ]]; then
    echo -e "  ${RED}MISSING${NC}  ${label}"
    echo "           Expected at: ${filepath}" >&2
    fail=1
    return
  fi

  local actual
  actual="$(sha256sum "${filepath}" | awk '{print $1}')"

  if [[ "${actual}" == "${expected}" ]]; then
    echo -e "  ${GREEN}OK${NC}       ${label}"
  else
    echo -e "  ${RED}MISMATCH${NC} ${label}"
    echo "           Expected : ${expected}" >&2
    echo "           Got      : ${actual}" >&2
    fail=1
  fi
}

echo "Verifying Servy 7.3 vendor parts..."
echo ""

verify_file \
  "${VENDOR_DIR}/servy-7.3-x64-portable.7z.part-aa" \
  "023f5a59f3346b7552261cdc273b156fa10df55330b138be20ef4209d929b1ba" \
  "servy-7.3-x64-portable.7z.part-aa"

verify_file \
  "${VENDOR_DIR}/servy-7.3-x64-portable.7z.part-ab" \
  "8b392b9a3a8bcb32b05f6ecc6526ea85d0ea6c9556826a5249c268b7237c5930" \
  "servy-7.3-x64-portable.7z.part-ab"

echo ""
if [[ "${fail}" -ne 0 ]]; then
  echo "ERROR: One or more parts failed verification." >&2
  echo "       Re-download or re-split the archive into prebuilt-binaries/servy/" >&2
  exit 1
fi

echo "All parts verified successfully."