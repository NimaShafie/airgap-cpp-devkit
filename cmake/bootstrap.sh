#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# cmake/bootstrap.sh
#
# PURPOSE: Install CMake 4.3.0 from vendored prebuilt binaries (default),
#          or build from vendored source (--build-from-source).
#
# USAGE:
#   bash cmake/bootstrap.sh                    # prebuilt (default)
#   bash cmake/bootstrap.sh --build-from-source
#   bash cmake/bootstrap.sh --rebuild          # force re-install
#   bash cmake/bootstrap.sh --prefix /custom/path
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/cmake"
CMAKE_VERSION="4.3.0"

BUILD_FROM_SOURCE=false
REBUILD=false
PREFIX_OVERRIDE=""

for arg in "$@"; do
    case "${arg}" in
        --build-from-source) BUILD_FROM_SOURCE=true ;;
        --rebuild)           REBUILD=true ;;
        --prefix)            shift; PREFIX_OVERRIDE="$1" ;;
        *) ;;
    esac
done

# Re-parse for --prefix since positional shift doesn't work in for loop
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX_OVERRIDE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "cmake" "${CMAKE_VERSION}"
install_log_capture_start

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    Linux*)                PLATFORM="linux"   ;;
    *) echo "[ERROR] Unsupported platform: $(uname -s)"; exit 1 ;;
esac

CMAKE_BIN="${INSTALL_BIN_DIR}/cmake"
[[ "${PLATFORM}" == "windows" ]] && CMAKE_BIN="${INSTALL_BIN_DIR}/cmake.exe"

if [[ -f "${CMAKE_BIN}" ]] && [[ "${REBUILD}" == "false" ]]; then
    INSTALLED_VER=$("${CMAKE_BIN}" --version 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")
    echo "[INFO] CMake already installed at ${CMAKE_BIN} (${INSTALLED_VER})"
    echo "       Use --rebuild to force re-installation."
    echo ""
    exit 0
fi

if [[ ! -d "${PREBUILT_DIR}" ]]; then
    echo "[ERROR] prebuilt-binaries submodule not initialized."
    echo "        Run: bash scripts/setup-prebuilt-submodule.sh"
    exit 1
fi

_verify_sha256() {
    local file="$1" expected="$2"
    if [[ ! -f "${file}" ]]; then
        echo "[ERROR] File not found: ${file}"; exit 1
    fi
    local actual
    actual="$(sha256sum "${file}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "[ERROR] SHA256 mismatch: ${file}"
        echo "        Expected : ${expected}"
        echo "        Got      : ${actual}"
        exit 1
    fi
    echo "[OK]   SHA256 verified: $(basename "${file}")"
}

_extract_zip() {
    local zip_file="$1" dest_dir="$2"
    mkdir -p "${dest_dir}"
    if command -v 7z &>/dev/null; then
        7z x "${zip_file}" -o"${dest_dir}" -y > /dev/null
    else
        local win_zip win_dest
        win_zip="$(cygpath -w "${zip_file}")"
        win_dest="$(cygpath -w "${dest_dir}")"
        powershell.exe -NoProfile -Command \
            "Expand-Archive -LiteralPath '${win_zip}' -DestinationPath '${win_dest}' -Force"
    fi
}

if [[ "${BUILD_FROM_SOURCE}" == "false" ]]; then

    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "${WORK_DIR}"' EXIT

    if [[ "${PLATFORM}" == "linux" ]]; then
        PART_AA="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz.part-aa"
        PART_AB="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz.part-ab"
        ASSEMBLED="${WORK_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"

        echo "[INFO] Verifying parts..."
        _verify_sha256 "${PART_AA}" "57d532fe7e398e16c16b07a01313a74cf71b03b9ddb39493f337e3598d7838e5"
        _verify_sha256 "${PART_AB}" "0fe83ca763e44f555794cce952c7a6bc7484841a8ecff4de23a43f2e863dd738"

        im_progress_start "Reassembling archive"
        cat "${PART_AA}" "${PART_AB}" > "${ASSEMBLED}"
        im_progress_stop "Archive reassembled"

        im_progress_start "Extracting cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
        tar -xzf "${ASSEMBLED}" -C "${WORK_DIR}"
        im_progress_stop "Extraction complete"

        EXTRACTED_DIR="${WORK_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64"

        im_progress_start "Installing to ${INSTALL_PREFIX}"
        mkdir -p "${INSTALL_PREFIX}"
        cp -r "${EXTRACTED_DIR}/." "${INSTALL_PREFIX}/"
        im_progress_stop "Installation complete"

    elif [[ "${PLATFORM}" == "windows" ]]; then
        PART_AA="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64.zip.part-aa"
        PART_AB="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64.zip.part-ab"
        ASSEMBLED="${WORK_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64.zip"

        echo "[INFO] Verifying parts..."
        _verify_sha256 "${PART_AA}" "4ac8f0d10b7d771e28fa5ecba9f5683756b6327ebfdbd66c552f430c3655ba59"
        _verify_sha256 "${PART_AB}" "bf4abc210d2c83ce6542de3158cbd8239e09c24605718095b68d1f1c1094a113"

        im_progress_start "Reassembling archive"
        cat "${PART_AA}" "${PART_AB}" > "${ASSEMBLED}"
        im_progress_stop "Archive reassembled"

        im_progress_start "Extracting cmake-${CMAKE_VERSION}-windows-x86_64.zip"
        _extract_zip "${ASSEMBLED}" "${WORK_DIR}"
        im_progress_stop "Extraction complete"

        EXTRACTED_DIR="${WORK_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64"
        if [[ ! -d "${EXTRACTED_DIR}" ]]; then
            echo "[ERROR] Expected extracted directory not found: ${EXTRACTED_DIR}"
            ls "${WORK_DIR}"
            exit 1
        fi

        im_progress_start "Installing to ${INSTALL_PREFIX}"
        mkdir -p "${INSTALL_PREFIX}"
        cp -r "${EXTRACTED_DIR}/." "${INSTALL_PREFIX}/"
        im_progress_stop "Installation complete"
    fi

    BUILD_TYPE="prebuilt"

else

    SOURCE_TARBALL="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}.tar.gz"
    echo "[INFO] Verifying source tarball..."
    _verify_sha256 "${SOURCE_TARBALL}" "f51b3c729f85d8dde46a92c071d2826ea6afb77d850f46894125de7cc51baa77"

    if ! command -v g++ &>/dev/null && ! command -v c++ &>/dev/null; then
        echo "[ERROR] No C++ compiler found."
        echo "        Linux  : sudo dnf install gcc-c++"
        echo "        Windows: ensure WinLibs GCC is on PATH"
        exit 1
    fi

    BUILD_WORK="$(mktemp -d)"
    trap 'rm -rf "${BUILD_WORK}"' EXIT

    im_progress_start "Extracting source tarball"
    tar -xzf "${SOURCE_TARBALL}" -C "${BUILD_WORK}"
    im_progress_stop "Source extracted"

    SRC_DIR="${BUILD_WORK}/cmake-${CMAKE_VERSION}"
    mkdir -p "${BUILD_WORK}/cmake-build"
    cd "${BUILD_WORK}/cmake-build"

    im_progress_start "Running CMake bootstrap"
    "${SRC_DIR}/bootstrap" \
        --prefix="${INSTALL_PREFIX}" \
        --parallel="$(nproc 2>/dev/null || echo 4)" \
        --no-system-curl \
        -- -DCMAKE_USE_OPENSSL=OFF
    im_progress_stop "Bootstrap complete"

    im_progress_start "Building CMake (10-20 min)"
    make -j"$(nproc 2>/dev/null || echo 4)"
    im_progress_stop "Build complete"

    im_progress_start "Installing to ${INSTALL_PREFIX}"
    make install
    im_progress_stop "Installation complete"

    cd "${REPO_ROOT}"
    BUILD_TYPE="source"
fi

echo ""
echo "[INFO] Verifying installation..."
if ! "${CMAKE_BIN}" --version &>/dev/null; then
    echo "[ERROR] cmake binary not functional after install."
    exit 1
fi
INSTALLED_VER=$("${CMAKE_BIN}" --version | head -1 | awk '{print $3}')

install_receipt_write "success" \
    "cmake:${CMAKE_BIN}"

echo "Build type   : ${BUILD_TYPE}" >> "${INSTALL_RECEIPT}"

install_env_register "${INSTALL_BIN_DIR}"

install_mode_print_footer "success" \
    "cmake:${CMAKE_BIN}"

echo "  cmake ${INSTALLED_VER} installed successfully."
echo ""
echo "  Add to PATH if needed:"
if [[ "${PLATFORM}" == "linux" ]]; then
    echo "    export PATH=\"${INSTALL_BIN_DIR}:\$PATH\""
else
    echo "    export PATH=\"$(cygpath -u "${INSTALL_BIN_DIR}" 2>/dev/null || echo "${INSTALL_BIN_DIR}"):\$PATH\""
fi
echo ""