#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/gcc/linux/cross/setup.sh
#
# Verifies, reassembles, and installs GCC 15.2 for Linux (x86_64).
# Toolchain source: tttapa/toolchains (Rocky 8 / RHEL 8 compatible).
# Installs to system-wide or per-user path based on available privileges.
#
# The tttapa toolchain uses prefixed binaries (x86_64-bionic-linux-gnu-gcc).
# This script creates unprefixed symlinks (gcc, g++, etc.) so the toolchain
# works transparently with CMake and other build tools.
#
# USAGE:
#   bash toolchains/gcc/linux/cross/setup.sh [--verify] [--dry-run] [--prefix <path>]
#
# OPTIONS:
#   --verify          Verify SHA256 checksums only — no installation
#   --dry-run         Show what would be installed without installing
#   --prefix <path>   Install to a custom path instead of auto-detected
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Linux only
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  Linux*) ;;
  *)
    echo "[ERROR] toolchains/gcc/linux/cross/setup.sh is for Linux only." >&2
    echo "        For Windows, use toolchains/gcc/windows/ instead." >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Source shared install-mode library
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"

TOOL_NAME="toolchains/gcc/linux/cross"
GCC_VERSION="15.2"
TOOLCHAIN_PREFIX="x86_64-bionic-linux-gnu"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
VERIFY_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)   VERIFY_ONLY=true; shift ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --prefix)   INSTALL_PREFIX_OVERRIDE="$2"; shift 2 ;;
    --help)
      echo "Usage: bash toolchains/gcc/linux/cross/setup.sh [--verify] [--dry-run] [--prefix <path>]"
      echo ""
      echo "  (no args)         Verify, reassemble, and install GCC ${GCC_VERSION}"
      echo "  --verify          Verify SHA256 checksums only — no installation"
      echo "  --dry-run         Show what would be installed without installing"
      echo "  --prefix <path>   Install to a custom path"
      exit 0
      ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Initialise install mode
# ---------------------------------------------------------------------------
install_mode_init "${TOOL_NAME}" "${GCC_VERSION}"
install_log_capture_start

VENDOR_DIR="${SCRIPT_DIR}/vendor"

# ---------------------------------------------------------------------------
# Filenames and hashes
# ---------------------------------------------------------------------------
TARBALL="x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz"
PART_AA="${TARBALL}.part-aa"
PART_AB="${TARBALL}.part-ab"
PART_AC="${TARBALL}.part-ac"
EXPECTED_SHA_AA="84e09929876ceec7b5d519921c38be05196f3b13bea150f13ac54156cb371ed8"
EXPECTED_SHA_AB="136429b957e94395565619f6d3c18201d6eb82ba420c131f3090d29d5d4fd853"
EXPECTED_SHA_AC="5d736c51a69cb2157cd0f95e0c418fd3dcb9a3eba15c2b36a59e640cd5345aeb"
EXPECTED_SHA_FULL="92cd7d00efa27298b6a2c7956afc6df4132051846c357547f278a52de56e7762"

# ---------------------------------------------------------------------------
# SHA256 verification helper
# ---------------------------------------------------------------------------
verify_sha256() {
  local file="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -f "${file}" ]]; then
    echo "[ERROR] Missing file: ${file}"
    exit 1
  fi

  local actual
  actual="$(sha256sum "${file}" | awk '{print $1}')"

  if [[ "${actual}" == "${expected}" ]]; then
    echo "[OK]   SHA256 verified: ${label}"
  else
    echo "[ERROR] SHA256 mismatch: ${label}"
    echo "        Expected: ${expected}"
    echo "        Actual:   ${actual}"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Verify split parts
# ---------------------------------------------------------------------------
verify_parts() {
  echo "[INFO] Verifying split parts..."
  verify_sha256 "${VENDOR_DIR}/${PART_AA}" "${EXPECTED_SHA_AA}" "${PART_AA}"
  verify_sha256 "${VENDOR_DIR}/${PART_AB}" "${EXPECTED_SHA_AB}" "${PART_AB}"
  verify_sha256 "${VENDOR_DIR}/${PART_AC}" "${EXPECTED_SHA_AC}" "${PART_AC}"
}

# ---------------------------------------------------------------------------
# Reassemble tarball from parts
# ---------------------------------------------------------------------------
reassemble() {
  local tarball_path="${VENDOR_DIR}/${TARBALL}"

  if [[ -f "${tarball_path}" ]]; then
    echo "[INFO] Tarball already exists — verifying..."
    verify_sha256 "${tarball_path}" "${EXPECTED_SHA_FULL}" "${TARBALL}"
    return
  fi

  im_progress_start "Reassembling tarball from parts"
  cat "${VENDOR_DIR}/${PART_AA}" \
      "${VENDOR_DIR}/${PART_AB}" \
      "${VENDOR_DIR}/${PART_AC}" \
      > "${tarball_path}"
  im_progress_stop "Tarball reassembled"

  verify_sha256 "${tarball_path}" "${EXPECTED_SHA_FULL}" "${TARBALL}"
}

# ---------------------------------------------------------------------------
# Detect existing GCC and inform user
# ---------------------------------------------------------------------------
detect_system_gcc() {
  local found=""
  for cmd in gcc g++ gcc-15 g++-15; do
    if command -v "${cmd}" &>/dev/null; then
      local ver
      ver="$("${cmd}" --version 2>&1 | head -1)"
      found="${found}  ${cmd} → ${ver}\n"
    fi
  done

  if [[ -n "${found}" ]]; then
    echo "[INFO] Existing GCC found on PATH:"
    printf "${found}"
    echo "[INFO] The devkit GCC 15.2 will be installed alongside."
    echo "[INFO] It will NOT override your system GCC unless you run:"
    echo "[INFO]   source toolchains/gcc/linux/cross/scripts/env-setup.sh"
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Create unprefixed symlinks
#
# The tttapa toolchain ships binaries as x86_64-bionic-linux-gnu-gcc etc.
# We create plain gcc/g++/etc. symlinks so CMake and build systems work
# without extra configuration.
# ---------------------------------------------------------------------------
create_symlinks() {
  local bin_dir="${INSTALL_PREFIX}/bin"
  local prefix="${TOOLCHAIN_PREFIX}"

  echo "[INFO] Creating unprefixed symlinks in ${bin_dir}..."

  local tools=(
    gcc g++ cpp c++ cc
    ar as nm ld ranlib strip objcopy objdump readelf size strings
    addr2line gprof gdb
  )

  local created=0
  for tool in "${tools[@]}"; do
    local prefixed="${bin_dir}/${prefix}-${tool}"
    local unprefixed="${bin_dir}/${tool}"

    if [[ -f "${prefixed}" ]] && [[ ! -e "${unprefixed}" ]]; then
      ln -sf "${prefixed}" "${unprefixed}"
      (( created++ )) || true
    fi
  done

  echo "[OK]   Created ${created} symlinks"
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install_gcc() {
  local tarball_path="${VENDOR_DIR}/${TARBALL}"

  echo "[INFO] Installing GCC ${GCC_VERSION} to: ${INSTALL_PREFIX}"
  mkdir -p "${INSTALL_PREFIX}"

  im_progress_start "Extracting GCC ${GCC_VERSION} toolchain"
  # The tarball contains x-tools/x86_64-bionic-linux-gnu/ — strip 2 components
  tar -xJf "${tarball_path}" -C "${INSTALL_PREFIX}" \
      --strip-components=2
  im_progress_stop "Extraction complete"

  # Create unprefixed symlinks
  create_symlinks

  # Verify via prefixed binary (the real executable)
  local gcc_bin="${INSTALL_PREFIX}/bin/${TOOLCHAIN_PREFIX}-gcc"
  local gxx_bin="${INSTALL_PREFIX}/bin/${TOOLCHAIN_PREFIX}-g++"

  if [[ ! -f "${gcc_bin}" ]]; then
    echo "[ERROR] Installation failed — ${TOOLCHAIN_PREFIX}-gcc not found: ${gcc_bin}"
    exit 1
  fi

  local gcc_ver gxx_ver
  gcc_ver="$("${gcc_bin}" --version 2>&1 | head -1)"
  gxx_ver="$("${gxx_bin}" --version 2>&1 | head -1)"

  echo "[OK]   ${gcc_ver}"
  echo "[OK]   ${gxx_ver}"

  # Also confirm symlinks work
  local gcc_sym="${INSTALL_PREFIX}/bin/gcc"
  if [[ -L "${gcc_sym}" ]]; then
    echo "[OK]   Symlink: gcc → ${TOOLCHAIN_PREFIX}-gcc"
  fi

  install_receipt_write "success" \
    "${TOOLCHAIN_PREFIX}-gcc:${gcc_bin}" \
    "${TOOLCHAIN_PREFIX}-g++:${gxx_bin}" \
    "gcc (symlink):${INSTALL_PREFIX}/bin/gcc" \
    "g++ (symlink):${INSTALL_PREFIX}/bin/g++"

  install_mode_print_footer "success" \
    "gcc:${INSTALL_PREFIX}/bin/gcc" \
    "g++:${INSTALL_PREFIX}/bin/g++"

  echo "To activate GCC ${GCC_VERSION} in your current shell:"
  echo "  source toolchains/gcc/linux/cross/scripts/env-setup.sh"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
detect_system_gcc
verify_parts

if [[ "${VERIFY_ONLY}" == true ]]; then
  echo "[OK]   Verification complete — no installation performed."
  exit 0
fi

if [[ "${DRY_RUN}" == true ]]; then
  echo "[DRY-RUN] Would reassemble tarball and install to: ${INSTALL_PREFIX}"
  exit 0
fi

reassemble
install_gcc