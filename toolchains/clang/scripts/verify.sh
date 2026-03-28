#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang/scripts/verify.sh
#
# Verifies SHA256 checksums of all vendored toolchains/clang split parts.
# Only checks assets relevant to the current platform and component.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ is inside toolchains/clang/scripts/ — repo root is 2 levels up
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/clang"

COMPONENT="${1:-all}"
OS="${2:-linux}"

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

echo "Verifying toolchains/clang vendor assets (${OS}, component=${COMPONENT})..."
echo ""

# ---------------------------------------------------------------------------
# clang-linux — official LLVM 22.1.2 prebuilt (Ubuntu-built, GLIBC 2.29+)
# NOTE: Requires GLIBC 2.29+ — not compatible with RHEL 8 (GLIBC 2.28)
#       Use clang-rhel8 component for RHEL 8 targets.
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]] && [[ "${COMPONENT}" == "all" || "${COMPONENT}" == "clang" ]]; then
  verify_file \
    "${VENDOR_DIR}/clang-linux/toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-aa" \
    "b02e4061f964cd5b930c2229ee75f3884165069017f663478804a8ff784697f4" \
    "toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-aa"
  verify_file \
    "${VENDOR_DIR}/clang-linux/toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ab" \
    "1072c3d5f2bec9fce1d37f66a6ccda6a48c44422e39fd3f963c8cd563bc24a80" \
    "toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ab"
  verify_file \
    "${VENDOR_DIR}/clang-linux/toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ac" \
    "e68779f0738c388bdb4cb68c0c1fbc9a02778faf67d536a8ab9eee50b763256f" \
    "toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ac"
fi

# ---------------------------------------------------------------------------
# clang-rhel8 — RHEL 8 native clang 20.1.8 RPMs (GLIBC 2.28 compatible)
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]] && [[ "${COMPONENT}" == "all" || "${COMPONENT}" == "clang-rhel8" ]]; then
  verify_file \
    "${VENDOR_DIR}/clang-rhel8/clang-20.1.8-rhel8-rpms.tar.part-aa" \
    "3dd0b1bf8bc4f46387fbe289016d1e94b41978c4433ef4d14da6705f0859d7d6" \
    "clang-20.1.8-rhel8-rpms.tar.part-aa"
  verify_file \
    "${VENDOR_DIR}/clang-rhel8/clang-20.1.8-rhel8-rpms.tar.part-ab" \
    "1e41c30b62cdf2ce0f9c46b4d9c5681c6b1b4a3c19b5281a5d857ecbc2caadc5" \
    "clang-20.1.8-rhel8-rpms.tar.part-ab"
fi

# ---------------------------------------------------------------------------
# llvm-mingw Linux cross-compiler — Linux only
# ---------------------------------------------------------------------------
if [[ "${OS}" == "linux" ]] && [[ "${COMPONENT}" == "all" || "${COMPONENT}" == "mingw" ]]; then
  verify_file \
    "${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-aa" \
    "f62fb01834060daad730f25844064d53abfc99fd0db8c244d72c292cfd99921d" \
    "llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-aa"
  verify_file \
    "${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-ab" \
    "d6996772dcf79068515fcbcd58e640ee542357c477dd8121323d89037fb80483" \
    "llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-ab"
fi

# ---------------------------------------------------------------------------
# llvm-mingw Windows native — Windows only
# ---------------------------------------------------------------------------
if [[ "${OS}" == "windows" ]] && [[ "${COMPONENT}" == "all" || "${COMPONENT}" == "mingw" ]]; then
  verify_file \
    "${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-aa" \
    "9b9b360a5cec496ea9765aa61f268be20200ccf77ffbab1998879cd6f64d3c5a" \
    "llvm-mingw-20260324-ucrt-x86_64.zip.part-aa"
  verify_file \
    "${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-ab" \
    "8b8d718ecf78123a47092561b116ef5b9239dbc7d87ccf9597e3fec1f4b46bc7" \
    "llvm-mingw-20260324-ucrt-x86_64.zip.part-ab"
  verify_file \
    "${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-ac" \
    "2472ab27d8935807aa83c23ab1da8bd712401b4a64d161760be39fd855b1df7e" \
    "llvm-mingw-20260324-ucrt-x86_64.zip.part-ac"
  verify_file \
    "${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-ad" \
    "edd1b68decb0a37c69ac00ff2fbf3e040de2adaa50b1ad3e3428d18629e41085" \
    "llvm-mingw-20260324-ucrt-x86_64.zip.part-ad"
fi

echo ""
if [[ "${fail}" -ne 0 ]]; then
  echo "ERROR: One or more parts failed verification." >&2
  exit 1
fi
echo "All assets verified successfully."