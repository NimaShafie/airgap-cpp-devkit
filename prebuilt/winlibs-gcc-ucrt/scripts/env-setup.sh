#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/env-setup.sh
#
# Add the WinLibs GCC UCRT toolchain to the current shell session.
# Source this file — do not execute it.
#
# USAGE:
#   source scripts/env-setup.sh [x86_64|i686] [install_dir]
#
# install_dir is auto-detected from the install receipt if not specified.
# Falls back to the legacy in-repo toolchain/ path if nothing else is found.
# =============================================================================

_winlibs_setup() {
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local MODULE_ROOT
  MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  local REPO_ROOT
  REPO_ROOT="$(cd "${MODULE_ROOT}/../.." && pwd)"
  local ARCH="${1:-x86_64}"
  local INSTALL_DIR="${2:-}"

  # Auto-detect install dir from receipt if not specified
  if [[ -z "${INSTALL_DIR}" ]]; then
    # Check admin path first
    local _pf
    _pf="$(cygpath -u "${PROGRAMFILES:-/c/Program Files}" 2>/dev/null || echo "/c/Program Files")"
    local admin_path="${_pf}/airgap-cpp-devkit/winlibs-gcc-ucrt/${ARCH}"
    local user_path
    local _lad
    _lad="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null || echo "${HOME}/AppData/Local")"
    user_path="${_lad}/airgap-cpp-devkit/winlibs-gcc-ucrt/${ARCH}"
    local legacy_path="${MODULE_ROOT}/toolchain/${ARCH}"

    if [[ -d "${admin_path}" ]]; then
      INSTALL_DIR="${admin_path}"
    elif [[ -d "${user_path}" ]]; then
      INSTALL_DIR="${user_path}"
    elif [[ -d "${legacy_path}" ]]; then
      INSTALL_DIR="${legacy_path}"
    else
      echo "[env-setup] ERROR: WinLibs not found. Run setup.sh first." >&2
      return 1
    fi
  fi

  local EXTRACT_ROOT
  case "${ARCH}" in
    x86_64) EXTRACT_ROOT="mingw64" ;;
    i686)   EXTRACT_ROOT="mingw32" ;;
    *) echo "[env-setup] ERROR: Unknown arch '${ARCH}'." >&2; return 1 ;;
  esac

  local BIN_DIR="${INSTALL_DIR}/${EXTRACT_ROOT}/bin"
  if [[ ! -d "${BIN_DIR}" ]]; then
    echo "[env-setup] ERROR: Toolchain bin dir not found: ${BIN_DIR}" >&2
    echo "[env-setup]        Run setup.sh first." >&2
    return 1
  fi

  case ":${PATH}:" in
    *":${BIN_DIR}:"*) echo "[env-setup] Already on PATH: ${BIN_DIR}" ;;
    *) export PATH="${BIN_DIR}:${PATH}"
       echo "[env-setup] Added to PATH: ${BIN_DIR}" ;;
  esac

  export WINLIBS_GCC_ROOT="${INSTALL_DIR}/${EXTRACT_ROOT}"
  export WINLIBS_GCC_BIN="${BIN_DIR}"
  export WINLIBS_GCC_ARCH="${ARCH}"
  export WINLIBS_GCC_VERSION="15.2.0"
  export WINLIBS_MINGW_VERSION="13.0.0"
  export WINLIBS_CRT="ucrt"
  export WINLIBS_INSTALL_DIR="${INSTALL_DIR}"

  echo "[env-setup] WINLIBS_GCC_ROOT=${WINLIBS_GCC_ROOT}"
  echo "[env-setup] Toolchain active. Verify with: gcc --version"
}
_winlibs_setup "$@"
unset -f _winlibs_setup
