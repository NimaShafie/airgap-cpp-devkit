#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# gcc-linux/scripts/env-setup.sh
#
# Activates the devkit GCC 15.2 in the current shell by prepending its
# bin directory to PATH. Source this file — do not execute it directly.
#
# USAGE:
#   source gcc-linux/scripts/env-setup.sh
#   source gcc-linux/scripts/env-setup.sh --admin   (force system-wide path)
#   source gcc-linux/scripts/env-setup.sh --user    (force per-user path)
# =============================================================================

_gcc_detect_install_dir() {
  local mode="${1:-auto}"

  local admin_path="${HOME}/.local/share/airgap-cpp-devkit/gcc-linux"
  local user_path="${HOME}/.local/share/airgap-cpp-devkit/gcc-linux"

  # On Linux only — set correct paths
  admin_path="/opt/airgap-cpp-devkit/gcc-linux"
  user_path="${HOME}/.local/share/airgap-cpp-devkit/gcc-linux"

  case "${mode}" in
    --admin) echo "${admin_path}" ;;
    --user)  echo "${user_path}" ;;
    auto)
      if [[ -d "${admin_path}/bin" ]]; then
        echo "${admin_path}"
      elif [[ -d "${user_path}/bin" ]]; then
        echo "${user_path}"
      else
        echo ""
      fi
      ;;
  esac
}

_GCC_INSTALL_DIR="$(_gcc_detect_install_dir "${1:-auto}")"

if [[ -z "${_GCC_INSTALL_DIR}" ]]; then
  echo "[gcc-linux/env-setup.sh] GCC 15.2 not installed. Run: bash gcc-linux/bootstrap.sh" >&2
  return 1
fi

export PATH="${_GCC_INSTALL_DIR}/bin:${PATH}"

# Set CC/CXX so CMake and other build tools pick up the devkit GCC automatically
export CC="${_GCC_INSTALL_DIR}/bin/gcc"
export CXX="${_GCC_INSTALL_DIR}/bin/g++"

echo "[gcc-linux/env-setup.sh] GCC 15.2 active: ${_GCC_INSTALL_DIR}/bin/gcc"
echo "[gcc-linux/env-setup.sh] CC=${CC}"
echo "[gcc-linux/env-setup.sh] CXX=${CXX}"

unset _GCC_INSTALL_DIR
unset -f _gcc_detect_install_dir