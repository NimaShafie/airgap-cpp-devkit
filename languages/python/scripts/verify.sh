#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# python/scripts/verify.sh
#
# Offline SHA256 integrity check for all vendored Python 3.14.3 files.
# Detects platform automatically and checks the appropriate files.
#
# USAGE:
#   bash python/scripts/verify.sh
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

echo "airgap-cpp-devkit — Python 3.14.3 integrity check"
echo "=================================================="

case "$(uname -s)" in
  Linux*)
    check "${VENDOR_DIR}/cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz.part-aa" \
          "5a59d87c70f7dd15a31c668d34558fd7add43df7484b013c4648a5194796b406"
    check "${VENDOR_DIR}/cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz.part-ab" \
          "12f5f6d8af2ee1fa6946b1732e6733ddd504d729ca4a70cda76e7be3439985ff"

    # Check reassembled tarball if present
    TARBALL="${VENDOR_DIR}/cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz"
    if [[ -f "${TARBALL}" ]]; then
      check "${TARBALL}" "d4c6712210b69540ab4ed51825b99388b200e4f90ca4e53fbb5a67c2467feb48"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    check "${VENDOR_DIR}/python-3.14.3-embed-amd64.zip" \
          "ad4961a479dedbeb7c7d113253f8db1b1935586b73c27488712beec4f2c894e6"
    ;;
  *)
    echo "[ERROR] Unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]