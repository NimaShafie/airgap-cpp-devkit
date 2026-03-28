#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang/scripts/install-linux.sh
#
# Installs LLVM toolchain components on Linux (RHEL 8 / Rocky Linux).
#
# Components:
#   clang        Slim Clang/LLVM 22.1.2 (Ubuntu-built, requires GLIBC 2.29+)
#                NOTE: Not compatible with RHEL 8 (GLIBC 2.28)
#   clang-rhel8  Clang 20.1.8 native RHEL 8 RPMs (GLIBC 2.28 compatible)
#   mingw        llvm-mingw 20260324 cross-compiler (Linux -> Windows)
#
# USAGE:
#   bash scripts/install-linux.sh <all|clang|clang-rhel8|mingw> <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/clang"

COMPONENT="${1:-all}"
MODE="${2:-user}"
PREFIX_OVERRIDE="${3:-}"

if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_BASE="${PREFIX_OVERRIDE}"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_BASE="/opt/airgap-cpp-devkit/toolchains/clang"
else
  INSTALL_BASE="${HOME}/.local/share/airgap-cpp-devkit/toolchains/clang"
fi

CLANG_DIR="${INSTALL_BASE}/clang"
MINGW_DIR="${INSTALL_BASE}/llvm-mingw"

echo "[toolchains/clang] Install base : ${INSTALL_BASE}"
echo "[toolchains/clang] Component    : ${COMPONENT}"
echo ""

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

install_clang() {
  local PART_AA="${VENDOR_DIR}/clang-linux/toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-aa"
  local PART_AB="${VENDOR_DIR}/clang-linux/toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ab"
  local PART_AC="${VENDOR_DIR}/clang-linux/toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ac"
  local REASSEMBLED="${TMPDIR}/clang-slim.tar.xz"

  echo "[toolchains/clang] Reassembling clang slim tarball..."
  cat "${PART_AA}" "${PART_AB}" "${PART_AC}" > "${REASSEMBLED}"

  local ACTUAL
  ACTUAL="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
  local EXPECTED="1988d3c2a84af6e16e968787c5c072ecaa37f93405aa2a0ec4c38096a5f3e14c"
  if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
    echo "ERROR: Reassembled clang tarball SHA256 mismatch." >&2
    exit 1
  fi
  echo "[toolchains/clang] Reassembled tarball verified OK"

  mkdir -p "${CLANG_DIR}"
  echo "[toolchains/clang] Extracting to ${CLANG_DIR}..."
  tar -xJf "${REASSEMBLED}" -C "${CLANG_DIR}" --strip-components=1

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

  echo "[toolchains/clang] clang installed: ${CLANG_DIR}"
  "${CLANG_DIR}/bin/clang" --version | head -1 || \
    echo "WARNING: clang binary requires GLIBC 2.29+ — not available on RHEL 8. Use --component clang-rhel8 instead."
}

install_clang_rhel8() {
  local PART_AA="${VENDOR_DIR}/clang-rhel8/clang-20.1.8-rhel8-rpms.tar.part-aa"
  local PART_AB="${VENDOR_DIR}/clang-rhel8/clang-20.1.8-rhel8-rpms.tar.part-ab"
  local REASSEMBLED="${TMPDIR}/clang-rhel8-rpms.tar"
  local RPM_DIR="${TMPDIR}/clang-rpms"

  echo "[toolchains/clang] Reassembling clang RHEL 8 RPM tarball..."
  cat "${PART_AA}" "${PART_AB}" > "${REASSEMBLED}"

  local ACTUAL
  ACTUAL="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
  local EXPECTED="ce6af160506b5465ece4458a59f2b209ad5c20096a47f7cfd177001a5345de8f"
  if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
    echo "ERROR: Reassembled clang-rhel8 tarball SHA256 mismatch." >&2
    exit 1
  fi
  echo "[toolchains/clang] Reassembled tarball verified OK"

  mkdir -p "${RPM_DIR}"
  echo "[toolchains/clang] Extracting RPMs..."
  tar -xf "${REASSEMBLED}" -C "${RPM_DIR}"

  echo "[toolchains/clang] Installing clang 20.1.8 RPMs via rpm..."
  rpm -Uvh --nodeps --replacepkgs "${RPM_DIR}"/*.rpm

  # Patch clang cfg to use toolchains/gcc/linux/native-15 instead of toolchains/gcc/linux/native-14
  local CFG="/etc/clang/x86_64-redhat-linux-gnu-clang.cfg"
  if [[ -f "${CFG}" ]]; then
    sed -i 's|toolchains/gcc/linux/native-14|toolchains/gcc/linux/native-15|g' "${CFG}"
    sed -i 's|/toolchains/gcc/linux/native-15/root//usr/lib/gcc/x86_64-redhat-linux/14|/toolchains/gcc/linux/native-15/root//usr/lib/gcc/x86_64-redhat-linux/15|g' "${CFG}"
    echo "[toolchains/clang] Patched ${CFG} to use toolchains/gcc/linux/native-15"
  fi

  echo "[toolchains/clang] clang-rhel8 installed"
  clang --version | head -1 2>/dev/null || true
  echo "[toolchains/clang] clang binary: $(which clang 2>/dev/null || echo 'run: hash -r to refresh PATH')"
}

install_mingw() {
  local PART_AA="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-aa"
  local PART_AB="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-ab"
  local REASSEMBLED="${TMPDIR}/llvm-mingw.tar.xz"

  echo "[toolchains/clang] Reassembling llvm-mingw tarball..."
  cat "${PART_AA}" "${PART_AB}" > "${REASSEMBLED}"

  local ACTUAL
  ACTUAL="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
  local EXPECTED="f92b02c4f835470deb5ac5fb92ddb458239e80ddff9ce8867155679ee5f57ffc"
  if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
    echo "ERROR: Reassembled llvm-mingw tarball SHA256 mismatch." >&2
    exit 1
  fi
  echo "[toolchains/clang] Reassembled tarball verified OK"

  mkdir -p "${MINGW_DIR}"
  echo "[toolchains/clang] Extracting to ${MINGW_DIR}..."
  tar -xJf "${REASSEMBLED}" -C "${MINGW_DIR}" --strip-components=1

  echo "[toolchains/clang] llvm-mingw installed: ${MINGW_DIR}"
  "${MINGW_DIR}/bin/x86_64-w64-mingw32-clang" --version | head -1 || \
    echo "WARNING: llvm-mingw requires GLIBC 2.29+ — not available on RHEL 8."
}

case "${COMPONENT}" in
  all)         install_clang; echo ""; install_mingw ;;
  clang)       install_clang ;;
  clang-rhel8) install_clang_rhel8 ;;
  mingw)       install_mingw ;;
  *) echo "ERROR: Unknown component: ${COMPONENT}" >&2; exit 1 ;;
esac

echo ""
echo "[toolchains/clang] Installation complete."