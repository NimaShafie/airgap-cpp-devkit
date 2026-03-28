#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# python/bootstrap.sh
#
# Verifies, reassembles (Linux only), and installs a portable Python 3.14.3
# interpreter to the appropriate system-wide or per-user path.
# If Python is already on PATH, the devkit Python is installed alongside it.
# Use 'source python/scripts/env-setup.sh' to activate the devkit Python.
#
# USAGE:
#   bash python/bootstrap.sh [--verify] [--dry-run] [--prefix <path>]
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
# Source shared install-mode library
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"

TOOL_NAME="python"
PYTHON_VERSION="3.14.3"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
VERIFY_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)            VERIFY_ONLY=true; shift ;;
    --dry-run)           DRY_RUN=true; shift ;;
    --prefix)            INSTALL_PREFIX_OVERRIDE="$2"; shift 2 ;;
    --help)
      echo "Usage: bash python/bootstrap.sh [--verify] [--dry-run] [--prefix <path>]"
      echo ""
      echo "  (no args)         Verify, reassemble (Linux), and install Python ${PYTHON_VERSION}"
      echo "  --verify          Verify SHA256 checksums only — no installation"
      echo "  --dry-run         Show what would be installed without installing"
      echo "  --prefix <path>   Install to a custom path"
      exit 0
      ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Initialise install mode (sets INSTALL_PREFIX, INSTALL_LOG_FILE, etc.)
# ---------------------------------------------------------------------------
install_mode_init "${TOOL_NAME}" "${PYTHON_VERSION}"
install_log_capture_start

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
detect_platform() {
  case "$(uname -s)" in
    Linux*)             echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)
      echo "[ERROR] Unsupported platform: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

PLATFORM="$(detect_platform)"
VENDOR_DIR="${SCRIPT_DIR}/vendor"

# ---------------------------------------------------------------------------
# Detect any existing system Python and inform the user
# ---------------------------------------------------------------------------
detect_system_python() {
  local found=""
  # Check for python3 first, then python
  for cmd in python3 python python3.14; do
    if command -v "${cmd}" &>/dev/null; then
      local ver
      ver="$("${cmd}" --version 2>&1 || true)"
      found="${found}  ${cmd} → ${ver} ($(command -v "${cmd}"))\n"
    fi
  done

  if [[ -n "${found}" ]]; then
    echo "[INFO] Existing Python found on PATH:"
    printf "${found}"
    echo "[INFO] The devkit Python will be installed alongside."
    echo "[INFO] It will NOT override your system Python unless you run:"
    echo "[INFO]   source python/scripts/env-setup.sh"
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Platform-specific filenames and hashes
# ---------------------------------------------------------------------------
if [[ "${PLATFORM}" == "linux" ]]; then
  TARBALL="cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz"
  PART_AA="${TARBALL}.part-aa"
  PART_AB="${TARBALL}.part-ab"
  EXPECTED_SHA_AA="5a59d87c70f7dd15a31c668d34558fd7add43df7484b013c4648a5194796b406"
  EXPECTED_SHA_AB="12f5f6d8af2ee1fa6946b1732e6733ddd504d729ca4a70cda76e7be3439985ff"
  EXPECTED_SHA_FULL="d4c6712210b69540ab4ed51825b99388b200e4f90ca4e53fbb5a67c2467feb48"
else
  ZIP_FILE="python-3.14.3-embed-amd64.zip"
  EXPECTED_SHA_ZIP="ad4961a479dedbeb7c7d113253f8db1b1935586b73c27488712beec4f2c894e6"
fi

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
# Linux: verify parts
# ---------------------------------------------------------------------------
verify_linux() {
  echo "[INFO] Verifying split parts..."
  verify_sha256 "${VENDOR_DIR}/${PART_AA}" "${EXPECTED_SHA_AA}" "${PART_AA}"
  verify_sha256 "${VENDOR_DIR}/${PART_AB}" "${EXPECTED_SHA_AB}" "${PART_AB}"
}

# ---------------------------------------------------------------------------
# Linux: reassemble tarball from parts
# ---------------------------------------------------------------------------
reassemble_linux() {
  local tarball_path="${VENDOR_DIR}/${TARBALL}"

  if [[ -f "${tarball_path}" ]]; then
    echo "[INFO] Tarball already exists — verifying..."
    verify_sha256 "${tarball_path}" "${EXPECTED_SHA_FULL}" "${TARBALL}"
    return
  fi

  im_progress_start "Reassembling tarball from parts"
  cat "${VENDOR_DIR}/${PART_AA}" \
      "${VENDOR_DIR}/${PART_AB}" \
      > "${tarball_path}"
  im_progress_stop "Tarball reassembled"

  verify_sha256 "${tarball_path}" "${EXPECTED_SHA_FULL}" "${TARBALL}"
}

# ---------------------------------------------------------------------------
# Windows: verify zip
# ---------------------------------------------------------------------------
verify_windows() {
  echo "[INFO] Verifying embeddable package..."
  verify_sha256 "${VENDOR_DIR}/${ZIP_FILE}" "${EXPECTED_SHA_ZIP}" "${ZIP_FILE}"
}

# ---------------------------------------------------------------------------
# Install — Linux
# ---------------------------------------------------------------------------
install_linux() {
  local tarball_path="${VENDOR_DIR}/${TARBALL}"

  echo "[INFO] Installing Python ${PYTHON_VERSION} to: ${INSTALL_PREFIX}"
  mkdir -p "${INSTALL_PREFIX}"

  im_progress_start "Extracting Python ${PYTHON_VERSION}"
  tar -xzf "${tarball_path}" -C "${INSTALL_PREFIX}" --strip-components=1
  im_progress_stop "Extraction complete"

  local python_bin="${INSTALL_PREFIX}/bin/python3.14"
  if [[ ! -f "${python_bin}" ]]; then
    echo "[ERROR] Installation failed — binary not found: ${python_bin}"
    exit 1
  fi

  local installed_version
  installed_version="$("${python_bin}" --version 2>&1)"
  echo "[OK]   Installed: ${installed_version}"

  install_receipt_write "success" "python3.14:${python_bin}"
  install_mode_print_footer "success" "python3.14:${python_bin}"

  echo "To activate Python in your current shell:"
  echo "  source python/scripts/env-setup.sh"
}

# ---------------------------------------------------------------------------
# Install — Windows
# ---------------------------------------------------------------------------
install_windows() {
  local zip_path="${VENDOR_DIR}/${ZIP_FILE}"

  echo "[INFO] Installing Python ${PYTHON_VERSION} to: ${INSTALL_PREFIX}"
  mkdir -p "${INSTALL_PREFIX}"

  im_progress_start "Extracting Python ${PYTHON_VERSION}"
  unzip -q -o "${zip_path}" -d "${INSTALL_PREFIX}"
  im_progress_stop "Extraction complete"

  local python_bin="${INSTALL_PREFIX}/python.exe"
  if [[ ! -f "${python_bin}" ]]; then
    echo "[ERROR] Installation failed — python.exe not found: ${python_bin}"
    exit 1
  fi

  local installed_version
  installed_version="$("${python_bin}" --version 2>&1)"
  echo "[OK]   Installed: ${installed_version}"

  install_receipt_write "success" "python.exe:${python_bin}"
  install_mode_print_footer "success" "python.exe:${python_bin}"

  echo "To activate Python in your current shell:"
  echo "  source python/scripts/env-setup.sh"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
detect_system_python

if [[ "${PLATFORM}" == "linux" ]]; then
  verify_linux

  if [[ "${VERIFY_ONLY}" == true ]]; then
    echo "[OK]   Verification complete — no installation performed."
    exit 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo "[DRY-RUN] Would reassemble tarball and install to: ${INSTALL_PREFIX}"
    exit 0
  fi

  reassemble_linux
  install_linux

else
  verify_windows

  if [[ "${VERIFY_ONLY}" == true ]]; then
    echo "[OK]   Verification complete — no installation performed."
    exit 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo "[DRY-RUN] Would install to: ${INSTALL_PREFIX}"
    exit 0
  fi

  install_windows
fi