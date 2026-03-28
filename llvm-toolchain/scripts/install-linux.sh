#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# llvm-toolchain/scripts/install-linux.sh
#
# Installs LLVM toolchain components on Linux (RHEL 8 / Rocky Linux).
#
# Components:
#   clang   Slim Clang/LLVM 22.1.2 (clang, lld, llvm-ar, etc.)
#   mingw   llvm-mingw 20260324 cross-compiler (Linux → Windows)
#
# USAGE:
#   bash scripts/install-linux.sh <all|clang|mingw> <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/llvm-toolchain"

COMPONENT="${1:-all}"
MODE="${2:-user}"
PREFIX_OVERRIDE="${3:-}"

# Determine install base
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_BASE="${PREFIX_OVERRIDE}"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_BASE="/opt/airgap-cpp-devkit/llvm-toolchain"
else
  INSTALL_BASE="${HOME}/.local/share/airgap-cpp-devkit/llvm-toolchain"
fi

CLANG_DIR="${INSTALL_BASE}/clang"
MINGW_DIR="${INSTALL_BASE}/llvm-mingw"

echo "[llvm-toolchain] Install base : ${INSTALL_BASE}"
echo "[llvm-toolchain] Component    : ${COMPONENT}"
echo ""

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

# ---------------------------------------------------------------------------
# Install clang (Linux slim tarball)
# ---------------------------------------------------------------------------
install_clang() {
  local PART_AA="${VENDOR_DIR}/clang-linux/clang-llvm-22.1.2-linux-x64-slim.tar.xz.part-aa"
  local PART_AB="${VENDOR_DIR}/clang-linux/clang-llvm-22.1.2-linux-x64-slim.tar.xz.part-ab"
  local PART_AC="${VENDOR_DIR}/clang-linux/clang-llvm-22.1.2-linux-x64-slim.tar.xz.part-ac"
  local REASSEMBLED="${TMPDIR}/clang-slim.tar.xz"

  echo "[llvm-toolchain] Reassembling clang slim tarball..."
  cat "${PART_AA}" "${PART_AB}" "${PART_AC}" > "${REASSEMBLED}"

  # Verify reassembled
  local ACTUAL
  ACTUAL="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
  local EXPECTED="1988d3c2a84af6e16e968787c5c072ecaa37f93405aa2a0ec4c38096a5f3e14c"
  if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
    echo "ERROR: Reassembled clang tarball SHA256 mismatch." >&2
    echo "  Expected: ${EXPECTED}" >&2
    echo "  Got     : ${ACTUAL}" >&2
    exit 1
  fi
  echo "[llvm-toolchain] Reassembled tarball verified OK"

  mkdir -p "${CLANG_DIR}"
  echo "[llvm-toolchain] Extracting to ${CLANG_DIR}..."
  tar -xJf "${REASSEMBLED}" -C "${CLANG_DIR}" --strip-components=1

  # Create symlinks (were symlinks in original, failed on Windows extraction)
  cd "${CLANG_DIR}/bin"
  ln -sf clang-22 clang
  ln -sf clang-22 clang++
  ln -sf clang-22 clang-cpp
  ln -sf lld      ld.lld
  ln -sf lld      ld64.lld
  ln -sf llvm-ar  llvm-ranlib
  ln -sf llvm-objcopy llvm-strip
  chmod +x clang-22 lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-config llvm-symbolizer
  cd - > /dev/null

  echo "[llvm-toolchain] clang installed: ${CLANG_DIR}"
  "${CLANG_DIR}/bin/clang" --version | head -1
}

# ---------------------------------------------------------------------------
# Install llvm-mingw (Linux cross-compiler)
# ---------------------------------------------------------------------------
install_mingw() {
  local PART_AA="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-aa"
  local PART_AB="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-ab"
  local REASSEMBLED="${TMPDIR}/llvm-mingw.tar.xz"

  echo "[llvm-toolchain] Reassembling llvm-mingw tarball..."
  cat "${PART_AA}" "${PART_AB}" > "${REASSEMBLED}"

  local ACTUAL
  ACTUAL="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
  local EXPECTED="f92b02c4f835470deb5ac5fb92ddb458239e80ddff9ce8867155679ee5f57ffc"
  if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
    echo "ERROR: Reassembled llvm-mingw tarball SHA256 mismatch." >&2
    exit 1
  fi
  echo "[llvm-toolchain] Reassembled tarball verified OK"

  mkdir -p "${MINGW_DIR}"
  echo "[llvm-toolchain] Extracting to ${MINGW_DIR}..."
  tar -xJf "${REASSEMBLED}" -C "${MINGW_DIR}" --strip-components=1

  echo "[llvm-toolchain] llvm-mingw installed: ${MINGW_DIR}"
  "${MINGW_DIR}/bin/x86_64-w64-mingw32-clang" --version | head -1
}

# ---------------------------------------------------------------------------
# Run selected components
# ---------------------------------------------------------------------------
case "${COMPONENT}" in
  all)   install_clang; echo ""; install_mingw ;;
  clang) install_clang ;;
  mingw) install_mingw ;;
  *) echo "ERROR: Unknown component: ${COMPONENT}" >&2; exit 1 ;;
esac

echo ""
echo "[llvm-toolchain] Installation complete."
if [[ "${MODE}" == "user" ]]; then
  echo "[llvm-toolchain] NOTE: Add to PATH in ~/.bashrc:"
  echo "  export PATH=\"${CLANG_DIR}/bin:${MINGW_DIR}/bin:\${PATH}\""
fi