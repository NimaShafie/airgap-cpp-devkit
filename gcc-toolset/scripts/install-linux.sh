#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# gcc-toolset/scripts/install-linux.sh
#
# Installs gcc-toolset-15 RPMs on RHEL 8 / Rocky Linux 8.
# Requires root or sudo for rpm -Uvh.
#
# USAGE:
#   bash scripts/install-linux.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/gcc-toolset"

MODE="${1:-admin}"
PREFIX_OVERRIDE="${2:-}"

PART_AA="${VENDOR_DIR}/gcc-toolset-15-rhel8-rpms.tar.part-aa"
PART_AB="${VENDOR_DIR}/gcc-toolset-15-rhel8-rpms.tar.part-ab"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

REASSEMBLED="${TMPDIR}/gcc-toolset-15-rhel8-rpms.tar"
RPM_DIR="${TMPDIR}/rpms"

echo "[gcc-toolset] Reassembling RPM tarball..."
cat "${PART_AA}" "${PART_AB}" > "${REASSEMBLED}"

# Verify reassembled
ACTUAL="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
EXPECTED="3ec5f205da34dbd0ea9d06c28034a9fb878d6883a92cc8b922fd151bc7123072"
if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
  echo "ERROR: Reassembled tarball SHA256 mismatch." >&2
  echo "  Expected: ${EXPECTED}" >&2
  echo "  Got     : ${ACTUAL}" >&2
  exit 1
fi
echo "[gcc-toolset] Reassembled tarball verified OK"

mkdir -p "${RPM_DIR}"
echo "[gcc-toolset] Extracting RPMs..."
tar -xf "${REASSEMBLED}" -C "${RPM_DIR}"

echo "[gcc-toolset] Installing RPMs via rpm..."
# Use --nodeps since we're installing a set that satisfies its own deps
# --replacepkgs allows re-running idempotently
rpm -Uvh --nodeps --replacepkgs "${RPM_DIR}"/*.rpm

echo ""
echo "[gcc-toolset] Verifying installation..."
GCC_BIN="/opt/rh/gcc-toolset-15/root/usr/bin/gcc"
GPP_BIN="/opt/rh/gcc-toolset-15/root/usr/bin/g++"

if [[ -f "${GCC_BIN}" ]]; then
  echo "[gcc-toolset] gcc: $("${GCC_BIN}" --version | head -1)"
else
  echo "WARNING: gcc not found at expected path: ${GCC_BIN}" >&2
fi

if [[ -f "${GPP_BIN}" ]]; then
  echo "[gcc-toolset] g++: $("${GPP_BIN}" --version | head -1)"
fi

# Verify libstdc++ has GLIBCXX_3.4.30
LIBSTDCPP="/opt/rh/gcc-toolset-15/root/usr/lib/gcc/x86_64-redhat-linux/15/libstdc++.so"
if [[ ! -f "${LIBSTDCPP}" ]]; then
  LIBSTDCPP="$(find /opt/rh/gcc-toolset-15 -name 'libstdc++.so*' 2>/dev/null | head -1)"
fi
if [[ -n "${LIBSTDCPP}" ]] && [[ -f "${LIBSTDCPP}" ]]; then
  if strings "${LIBSTDCPP}" 2>/dev/null | grep -q "GLIBCXX_3.4.30"; then
    echo "[gcc-toolset] libstdc++ provides GLIBCXX_3.4.30+ ✓"
  fi
fi

# Patch clang cfg to use gcc-toolset-15 if present
CFG="/etc/clang/x86_64-redhat-linux-gnu-clang.cfg"
if [[ -f "${CFG}" ]]; then
  sed -i 's|gcc-toolset-14|gcc-toolset-15|g' "${CFG}"
  sed -i 's|/gcc-toolset-15/root//usr/lib/gcc/x86_64-redhat-linux/14|/gcc-toolset-15/root//usr/lib/gcc/x86_64-redhat-linux/15|g' "${CFG}"
  echo "[gcc-toolset] Patched ${CFG} to use gcc-toolset-15"
fi

echo ""
echo "[gcc-toolset] Installation complete."
echo "[gcc-toolset] Activate with: source /opt/rh/gcc-toolset-15/enable"
echo ""
echo "[gcc-toolset] To use libstdc++ for clang-format/tidy, set:"
echo "  export LD_LIBRARY_PATH=\"\$(scl enable gcc-toolset-15 -- bash -c 'echo \$LD_LIBRARY_PATH')\""
echo "  # or manually:"
LIBDIR="$(find /opt/rh/gcc-toolset-15 -name 'libstdc++.so*' 2>/dev/null | grep -v '/32' | xargs -I{} dirname {} 2>/dev/null | head -1 || echo '/opt/rh/gcc-toolset-15/root/usr/lib/gcc/x86_64-redhat-linux/15')"
echo "  export LD_LIBRARY_PATH=\"${LIBDIR}:\${LD_LIBRARY_PATH:-}\""