#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/7zip/scripts/verify.sh
#
# Verifies SHA256 checksums of all vendored 7-Zip assets.
# Checks only the files relevant to the current platform.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/7zip"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

OS="linux"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac

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

echo "Verifying 7-Zip 26.00 vendor assets (${OS})..."
echo ""

if [[ "${OS}" == "windows" ]]; then
  verify_file \
    "${VENDOR_DIR}/7z2600-x64.exe" \
    "6fe18d5b3080e39678cabfa6cef12cfb25086377389b803a36a3c43236a8a82c" \
    "7z2600-x64.exe (Windows installer)"

  verify_file \
    "${VENDOR_DIR}/7z2600-extra.7z" \
    "1cc38a9e3777ce0e4bbf84475672888a581d400633b0448fd973a7a6aa56cfdc" \
    "7z2600-extra.7z (Windows portable source)"
else
  verify_file \
    "${VENDOR_DIR}/7z2600-linux-x64.tar.xz" \
    "c74dc4a48492cde43f5fec10d53fb2a66f520e4a62a69d630c44cb22c477edc6" \
    "7z2600-linux-x64.tar.xz (Linux x64 binary)"
fi

echo ""
if [[ "${fail}" -ne 0 ]]; then
  echo "ERROR: One or more vendor assets failed verification." >&2
  echo "       Re-download the missing/corrupt files into dev-tools/7zip/vendor/" >&2
  exit 1
fi

echo "All assets verified successfully."