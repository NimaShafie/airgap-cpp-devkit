#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# languages/python/setup.sh
#
# Installs portable Python 3.14.4 for air-gapped environments.
# Also installs vendored pip packages from languages/python/pip-packages/.
#
# USAGE:
#   bash languages/python/setup.sh [OPTIONS]
#
# OPTIONS:
#   --prefix <path>   Override install prefix
#   --skip-pip        Skip pip package installation
#   --rebuild         Force reinstall even if already present
#   -h | --help       Print this help
#
# PLATFORMS:
#   Windows 11  (Git Bash / MINGW64) -- embeddable zip
#   RHEL 8 / Linux x86_64            -- standalone tar.gz (reassembled from parts)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PYTHON_VERSION="3.14.4"
TOOL_NAME="python"
SKIP_PIP=false
REBUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pip) SKIP_PIP=true; shift ;;
    --rebuild)  REBUILD=true;  shift ;;
    --prefix)   export INSTALL_PREFIX_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^[^#]/{/^#/!q; s/^# \?//; p}' "$0"
      exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  Linux*)                OS="linux"   ;;
  *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "${TOOL_NAME}" "${PYTHON_VERSION}"
install_log_capture_start

PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/languages/python"
PIP_PKG_DIR="${SCRIPT_DIR}/pip-packages"

# ---------------------------------------------------------------------------
# Check for existing install
# ---------------------------------------------------------------------------
if [[ -f "${INSTALL_RECEIPT}" && "${REBUILD}" == "false" ]]; then
  existing_ver="$(grep "^Version" "${INSTALL_RECEIPT}" 2>/dev/null | awk '{print $3}' || echo "")"
  if [[ "${existing_ver}" == "${PYTHON_VERSION}" ]]; then
    echo "  [OK]  Python ${PYTHON_VERSION} already installed at ${INSTALL_PREFIX}"
    echo "        Use --rebuild to force reinstall."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Install Python interpreter
# ---------------------------------------------------------------------------
_install_python() {
  mkdir -p "${INSTALL_PREFIX}"

  case "${OS}" in
    windows)
      local archive="${PREBUILT_DIR}/python-${PYTHON_VERSION}-embed-amd64.zip"
      local expected_sha="cda80a9b1e75c0f1b4f9872ca1b417f0d19bce32facc811aea9180e70fad5fb9"

      if [[ ! -f "${archive}" ]]; then
        echo "ERROR: Windows embeddable archive not found: ${archive}" >&2
        exit 1
      fi

      im_progress_start "Verifying python-${PYTHON_VERSION}-embed-amd64.zip"
      local actual_sha
      actual_sha="$(sha256sum "${archive}" | awk '{print $1}')"
      if [[ "${actual_sha}" != "${expected_sha}" ]]; then
        echo "ERROR: SHA256 mismatch" >&2
        echo "  Expected: ${expected_sha}" >&2
        echo "  Actual  : ${actual_sha}" >&2
        im_progress_stop "Verification failed"
        exit 1
      fi
      im_progress_stop "Verified"

      im_progress_start "Extracting Python ${PYTHON_VERSION} (Windows embeddable)"
      if command -v unzip &>/dev/null; then
        unzip -q -o "${archive}" -d "${INSTALL_PREFIX}"
      elif command -v 7z &>/dev/null; then
        7z x "${archive}" -o"${INSTALL_PREFIX}" -y > /dev/null
      else
        echo "ERROR: Need unzip or 7z to extract." >&2; exit 1
      fi
      im_progress_stop "Extracted"

      # Enable site-packages in embeddable Python
      local pth_file
      pth_file="$(find "${INSTALL_PREFIX}" -maxdepth 1 -name "python3*._pth" | head -1)"
      if [[ -n "${pth_file}" ]]; then
        sed -i 's/#import site/import site/' "${pth_file}"
        echo "  [OK]  Enabled site-packages in $(basename "${pth_file}")"
      fi
      ;;

    linux)
      local part_aa="${PREBUILT_DIR}/cpython-${PYTHON_VERSION}+20260408-x86_64-unknown-linux-gnu-install_only.tar.gz.part-aa"
      local part_ab="${PREBUILT_DIR}/cpython-${PYTHON_VERSION}+20260408-x86_64-unknown-linux-gnu-install_only.tar.gz.part-ab"
      # SHA256 of the reassembled archive
      local expected_sha="2431e22d39c0dee2c4d785250e2974bea863a61951a2e7edab88a14657a39d73"

      if [[ ! -f "${part_aa}" || ! -f "${part_ab}" ]]; then
        echo "ERROR: Linux standalone parts not found in ${PREBUILT_DIR}" >&2
        echo "       Expected: cpython-${PYTHON_VERSION}+20260408-x86_64-unknown-linux-gnu-install_only.tar.gz.part-{aa,ab}" >&2
        exit 1
      fi

      local tmp_archive
      tmp_archive="$(mktemp /tmp/cpython-XXXXXX.tar.gz)"
      trap "rm -f '${tmp_archive}'" EXIT

      im_progress_start "Reassembling Python ${PYTHON_VERSION} Linux standalone"
      cat "${part_aa}" "${part_ab}" > "${tmp_archive}"
      im_progress_stop "Reassembled"

      im_progress_start "Verifying reassembled archive"
      local actual_sha
      actual_sha="$(sha256sum "${tmp_archive}" | awk '{print $1}')"
      if [[ "${actual_sha}" != "${expected_sha}" ]]; then
        echo "ERROR: SHA256 mismatch after reassembly" >&2
        echo "  Expected: ${expected_sha}" >&2
        echo "  Actual  : ${actual_sha}" >&2
        im_progress_stop "Verification failed"
        exit 1
      fi
      im_progress_stop "Verified"

      im_progress_start "Extracting Python ${PYTHON_VERSION} (Linux standalone)"
      tar -xzf "${tmp_archive}" --strip-components=1 -C "${INSTALL_PREFIX}"
      im_progress_stop "Extracted"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Locate python binary
# ---------------------------------------------------------------------------
_python_bin() {
  case "${OS}" in
    windows) echo "${INSTALL_PREFIX}/python.exe" ;;
    linux)   echo "${INSTALL_PREFIX}/bin/python3" ;;
  esac
}

# ---------------------------------------------------------------------------
# Install vendored pip packages
# ---------------------------------------------------------------------------
_install_pip_packages() {
  if [[ ! -d "${PIP_PKG_DIR}" ]]; then
    echo "  [--]  pip-packages/ not found -- skipping pip installs."
    return 0
  fi

  local whl_count
  whl_count="$(find "${PIP_PKG_DIR}" -name "*.whl" | wc -l)"
  if [[ "${whl_count}" -eq 0 ]]; then
    echo "  [--]  No .whl files in pip-packages/ -- skipping."
    return 0
  fi

  local python_bin
  python_bin="$(_python_bin)"

  if [[ ! -f "${python_bin}" ]]; then
    echo "  [!!]  Python binary not found -- skipping pip." >&2
    return 0
  fi

  echo ""
  echo "  Installing vendored pip packages (${whl_count} wheels found)..."
  echo ""

  # Full package list with pinned versions matching vendored wheels
  local packages=(
    # Data science core
    "numpy==2.4.4"
    "pandas==3.0.2"
    "scipy"          # 1.17.1 Windows / 1.16.3 Linux -- pip picks correct platform wheel
    "scikit-learn==1.8.0"
    "matplotlib==3.10.8"
    # Visualization
    "plotly==6.7.0"
    "pillow==12.2.0"
    # Web application
    "streamlit==1.56.0"
    # Database
    "sqlalchemy==2.0.49"
    # HTTP
    "requests==2.33.1"
    # Data formats and serialization
    "PyYAML==6.0.3"
    "pydantic==2.12.5"
    "openpyxl==3.1.5"
    # Templating and configuration
    "Jinja2==3.1.6"
    "python-dotenv==1.2.2"
    # CLI and developer tools
    "click==8.3.2"
    "rich==14.3.3"
    "loguru==0.7.3"
    # Testing
    "pytest==9.0.3"
  )

  local installed=0 failed=0 skipped=0

  for pkg in "${packages[@]}"; do
    # Strip version specifier (e.g. "numpy==2.4.4" -> "numpy")
    local pkg_name="${pkg%%==*}"
    local pkg_name="${pkg_name%%>=*}"
    # Convert hyphens to underscores for filename matching (pip wheel convention)
    local pkg_underscore="${pkg_name//-/_}"
    local pkg_hyphen="${pkg_name//_/-}"

    # Check if any matching wheel exists before attempting install
    local whl_file
    whl_file="$(find "${PIP_PKG_DIR}" \
      \( -iname "${pkg_name}-*.whl" \
      -o -iname "${pkg_underscore}-*.whl" \
      -o -iname "${pkg_hyphen}-*.whl" \) \
      2>/dev/null | head -1 || true)"

    if [[ -z "${whl_file}" ]]; then
      printf "  [--]  %-22s not found in pip-packages/ -- skipped\n" "${pkg_name}"
      (( skipped++ )) || true
      continue
    fi

    printf "  [....] %-22s" "${pkg_name}"

    # streamlit on Linux: watchdog has no Linux wheel (hot-reload only, not required)
    # Install streamlit + all its deps except watchdog explicitly
    if [[ "${pkg_name}" == "streamlit" && "${OS}" == "linux" ]]; then
      local streamlit_deps=(
        "altair" "blinker" "cachetools" "click" "gitpython"
        "Jinja2" "numpy" "packaging" "pandas" "pillow"
        "plotly" "protobuf" "pyarrow" "pydeck" "requests"
        "rich" "tenacity" "toml" "tornado" "typing-extensions"
      )
      local sdep_ok=true
      for sdep in "${streamlit_deps[@]}"; do
        "${python_bin}" -m pip install \
            --quiet --no-index \
            --find-links="${PIP_PKG_DIR}" \
            "${sdep}" 2>/dev/null || true
      done
      if "${python_bin}" -m pip install \
          --quiet --no-index \
          --find-links="${PIP_PKG_DIR}" \
          --no-deps streamlit 2>/dev/null; then
        printf "  [OK] (watchdog skipped -- no Linux wheel)\n"
        (( installed++ )) || true
      else
        printf "  [!!] FAILED\n" >&2
        (( failed++ )) || true
      fi
      continue
    fi

    if "${python_bin}" -m pip install \
        --quiet --no-index \
        --find-links="${PIP_PKG_DIR}" \
        "${pkg}" 2>/dev/null; then
      printf "  [OK]\n"
      (( installed++ )) || true
    else
      printf "  [!!] FAILED\n" >&2
      (( failed++ )) || true
    fi
  done

  echo ""
  echo "  Results: ${installed} installed, ${skipped} skipped (wheel not present), ${failed} failed"
  echo "  Note: sqlite3 is Python stdlib -- no wheel required."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Python ${PYTHON_VERSION} -- Setup"
echo " Portable interpreter + vendored pip packages"
echo " Platform    : ${OS}"
echo " Install mode: ${INSTALL_MODE}"
echo "============================================================"
echo ""

_install_python

python_bin="$(_python_bin)"
if [[ ! -f "${python_bin}" ]]; then
  echo "ERROR: Python binary not found after install: ${python_bin}" >&2
  exit 1
fi

ver="$("${python_bin}" --version 2>&1)"
echo "  [OK]  ${ver}"

mkdir -p "${INSTALL_BIN_DIR}"

if [[ "${SKIP_PIP}" == "false" ]]; then
  _install_pip_packages
fi

case "${OS}" in
  windows) install_env_register "${INSTALL_PREFIX}" ;;
  linux)   install_env_register "${INSTALL_PREFIX}/bin" ;;
esac

install_receipt_write "success" "python:${python_bin}"
install_mode_print_footer "success" "python:${python_bin}"

echo ""
echo "  To activate:"
echo "    source languages/python/scripts/env-setup.sh"
echo ""