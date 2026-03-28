#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/gcc/linux/cross/scripts/verify.sh
#
# Offline SHA256 integrity check for all vendored GCC 15.2 files.
#
# USAGE:
#   bash toolchains/gcc/linux/cross/scripts/verify.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="${SCRIPT_DIR}/../vendor"

PASS=0
FAIL=0

check() {
  local file="$1"
  local expected="$2"

  if [[ ! -f "${file}" ]]; then
    echo "[MISSING] ${file}"
    (( FAIL++ )) || true
    return
  fi

  local actual
  actual="$(sha256sum "${file}" | awk '{print $1}')"

  if [[ "${actual}" == "${expected}" ]]; then
    echo "[OK]      $(basename "${file}")"
    (( PASS++ )) || true
  else
    echo "[FAIL]    $(basename "${file}")"
    echo "          expected: ${expected}"
    echo "          actual:   ${actual}"
    (( FAIL++ )) || true
  fi
}

echo "airgap-cpp-devkit — GCC 15.2 Linux integrity check"
echo "==================================================="

check "${VENDOR_DIR}/x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz.part-aa" \
      "84e09929876ceec7b5d519921c38be05196f3b13bea150f13ac54156cb371ed8"

check "${VENDOR_DIR}/x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz.part-ab" \
      "136429b957e94395565619f6d3c18201d6eb82ba420c131f3090d29d5d4fd853"

check "${VENDOR_DIR}/x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz.part-ac" \
      "5d736c51a69cb2157cd0f95e0c418fd3dcb9a3eba15c2b36a59e640cd5345aeb"

# Check reassembled tarball if present
TARBALL="${VENDOR_DIR}/x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz"
if [[ -f "${TARBALL}" ]]; then
  check "${TARBALL}" "92cd7d00efa27298b6a2c7956afc6df4132051846c357547f278a52de56e7762"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]