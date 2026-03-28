#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang/scripts/install-windows.sh
#
# Installs llvm-mingw 20260324 native Windows toolchain on Windows 11
# (Git Bash / MINGW64). Clang-linux component is Linux-only.
#
# USAGE:
#   bash scripts/install-windows.sh <all|clang|mingw> <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/clang"

COMPONENT="${1:-all}"
MODE="${2:-user}"
PREFIX_OVERRIDE="${3:-}"

# clang component is Linux-only
if [[ "${COMPONENT}" == "clang" ]]; then
  echo "[toolchains/clang] clang-linux component is Linux-only — skipping on Windows."
  exit 0
fi

# Determine install base
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_BASE="${PREFIX_OVERRIDE}"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_BASE="/c/Program Files/airgap-cpp-devkit/toolchains/clang"
else
  INSTALL_BASE="${LOCALAPPDATA}/airgap-cpp-devkit/toolchains/clang"
fi

MINGW_DIR="${INSTALL_BASE}/llvm-mingw"

echo "[toolchains/clang] Install base : ${INSTALL_BASE}"
echo "[toolchains/clang] Component    : mingw (Windows native)"
echo ""

# Find 7zip for extraction
SEVEN_Z=""
for candidate in \
  "/c/Program Files/7-Zip/7z.exe" \
  "${LOCALAPPDATA}/airgap-cpp-devkit/7zip/7za.exe" \
  "7z" "7za"; do
  if command -v "${candidate}" &>/dev/null 2>&1 || [[ -f "${candidate}" ]]; then
    SEVEN_Z="${candidate}"
    break
  fi
done

if [[ -z "${SEVEN_Z}" ]]; then
  echo "ERROR: No 7z/7za executable found." >&2
  echo "       Install 7-Zip first: bash dev-tools/7zip/setup.sh" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

# Reassemble zip
PART_AA="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-aa"
PART_AB="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-ab"
PART_AC="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-ac"
PART_AD="${VENDOR_DIR}/llvm-mingw/llvm-mingw-20260324-ucrt-x86_64.zip.part-ad"
REASSEMBLED="${TMPDIR}/llvm-mingw.zip"

echo "[toolchains/clang] Reassembling llvm-mingw Windows zip..."
cat "${PART_AA}" "${PART_AB}" "${PART_AC}" "${PART_AD}" > "${REASSEMBLED}"

ACTUAL="$(sha256sum "${REASSEMBLED}" | awk '{print $1}')"
EXPECTED="e6d3195ab6ee67f66651ae263b91e395cef3ef3af95d20f1004f84e9fe988116"
if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
  echo "ERROR: Reassembled zip SHA256 mismatch." >&2
  echo "  Expected: ${EXPECTED}" >&2
  echo "  Got     : ${ACTUAL}" >&2
  exit 1
fi
echo "[toolchains/clang] Reassembled zip verified OK"

mkdir -p "${MINGW_DIR}"
echo "[toolchains/clang] Extracting to ${MINGW_DIR}..."

EXTRACT_TMP="${TMPDIR}/extract"
mkdir -p "${EXTRACT_TMP}"
"${SEVEN_Z}" x "${REASSEMBLED}" -o"${EXTRACT_TMP}" -y > /dev/null

# The zip extracts to llvm-mingw-20260324-ucrt-x86_64/ — flatten one level
EXTRACTED_ROOT="${EXTRACT_TMP}/llvm-mingw-20260324-ucrt-x86_64"
if [[ ! -d "${EXTRACTED_ROOT}" ]]; then
  echo "ERROR: Expected extracted folder not found." >&2
  exit 1
fi

\cp -r "${EXTRACTED_ROOT}/." "${MINGW_DIR}/"
echo "[toolchains/clang] llvm-mingw installed: ${MINGW_DIR}"

# Verify
CLANG_EXE="${MINGW_DIR}/bin/clang.exe"
if [[ -f "${CLANG_EXE}" ]]; then
  echo "[toolchains/clang] Found: ${CLANG_EXE}"
  "${CLANG_EXE}" --version | head -1 || true
fi

# Register PATH
WIN_MINGW_DIR="$(cygpath -w "${MINGW_DIR}/bin")"
powershell.exe -NoProfile -NonInteractive -Command "
  \$scope = if ('${MODE}' -eq 'admin') { 'Machine' } else { 'User' }
  \$current = [Environment]::GetEnvironmentVariable('Path', \$scope)
  if (\$current -notlike '*${WIN_MINGW_DIR}*') {
    [Environment]::SetEnvironmentVariable('Path', \$current + ';${WIN_MINGW_DIR}', \$scope)
    Write-Host '[toolchains/clang] PATH updated (' + \$scope + ')'
  } else {
    Write-Host '[toolchains/clang] PATH already contains install dir'
  }
" 2>/dev/null || true

echo ""
echo "[toolchains/clang] Open a new terminal for PATH to take effect."