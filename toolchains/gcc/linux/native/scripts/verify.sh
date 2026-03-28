#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/gcc/linux/native/scripts/verify.sh
#
# Verifies SHA256 checksums of vendored toolchains/gcc/linux/native-15 split parts.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/gcc/linux/native"

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

echo "Verifying toolchains/gcc/linux/native vendor assets..."
echo ""

verify_file \
  "${VENDOR_DIR}/toolchains/gcc/linux/native-15-rhel8-rpms.tar.part-aa" \
  "b37ff1e3ede16ee6f295c697389c2e75e9bad216811290bef6c5bdb8f4b6db3c" \
  "toolchains/gcc/linux/native-15-rhel8-rpms.tar.part-aa"

verify_file \
  "${VENDOR_DIR}/toolchains/gcc/linux/native-15-rhel8-rpms.tar.part-ab" \
  "2e900efc4c53f614354b42508f4015bb3d4c8f1eb99eaf5507c6e029022abe7f" \
  "toolchains/gcc/linux/native-15-rhel8-rpms.tar.part-ab"

echo ""
if [[ "${fail}" -ne 0 ]]; then
  echo "ERROR: One or more parts failed verification." >&2
  exit 1
fi
echo "All assets verified successfully."