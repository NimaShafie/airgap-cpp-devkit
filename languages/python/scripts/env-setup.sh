#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# python/scripts/env-setup.sh
#
# Activates the devkit Python 3.14.3 in the current shell by prepending its
# bin directory to PATH. Source this file — do not execute it directly.
#
# USAGE:
#   source python/scripts/env-setup.sh
#   source python/scripts/env-setup.sh --admin   (force system-wide path)
#   source python/scripts/env-setup.sh --user    (force per-user path)
# =============================================================================

_python_detect_install_dir() {
  local mode="${1:-auto}"

  local admin_path user_path

  case "$(uname -s)" in
    Linux*)
      admin_path="/opt/airgap-cpp-devkit/python"
      user_path="${HOME}/.local/share/airgap-cpp-devkit/python"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      admin_path="/c/Program Files/airgap-cpp-devkit/python"
      user_path="${LOCALAPPDATA}/airgap-cpp-devkit/python"
      ;;
  esac

  case "${mode}" in
    --admin) echo "${admin_path}" ;;
    --user)  echo "${user_path}" ;;
    auto)
      if [[ -d "${admin_path}" ]]; then
        echo "${admin_path}"
      elif [[ -d "${user_path}" ]]; then
        echo "${user_path}"
      else
        echo ""
      fi
      ;;
  esac
}

_PYTHON_INSTALL_DIR="$(_python_detect_install_dir "${1:-auto}")"

if [[ -z "${_PYTHON_INSTALL_DIR}" ]]; then
  echo "[python/env-setup.sh] Python not installed. Run: bash python/bootstrap.sh" >&2
  return 1
fi

case "$(uname -s)" in
  Linux*)
    export PATH="${_PYTHON_INSTALL_DIR}/bin:${PATH}"
    echo "[python/env-setup.sh] Python 3.14.3 active: ${_PYTHON_INSTALL_DIR}/bin/python3.14"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    export PATH="${_PYTHON_INSTALL_DIR}:${PATH}"
    echo "[python/env-setup.sh] Python 3.14.3 active: ${_PYTHON_INSTALL_DIR}/python.exe"
    ;;
esac

unset _PYTHON_INSTALL_DIR
unset -f _python_detect_install_dir