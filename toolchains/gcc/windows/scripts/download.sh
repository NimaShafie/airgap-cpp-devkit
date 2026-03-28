#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/gcc/windows/scripts/download.sh
#
# PURPOSE: Run on a networked machine (online side of the air-gap).
#          Downloads the WinLibs GCC UCRT .7z, verifies its SHA256 against
#          the value pinned in manifest.json, then fetches the upstream
#          .sha256 sidecar from GitHub to cross-check as a second source.
#
# USAGE:
#   bash scripts/download.sh [x86_64|i686]     # default: x86_64
#
# RESULT:
#   vendor/<filename>.7z   — ready for sneakernet transfer to air-gapped host
#
# REQUIREMENTS (online machine):
#   curl or wget, sha256sum (standard on MINGW64/MSYS2/RHEL)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
VENDOR_DIR="${MODULE_ROOT}/vendor"

# ---------------------------------------------------------------------------
# Arg: architecture
# ---------------------------------------------------------------------------
ARCH="${1:-x86_64}"
if [[ "${ARCH}" != "x86_64" && "${ARCH}" != "i686" ]]; then
  echo "[ERROR] Unknown architecture '${ARCH}'. Use 'x86_64' or 'i686'." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse manifest (no jq dependency — pure bash/grep/sed)
# ---------------------------------------------------------------------------
parse_manifest_field() {
  # Usage: parse_manifest_field <block_key> <field>
  # Extracts a JSON string value from the assets.<arch> block.
  local block="$1"
  local field="$2"
  grep -A 30 "\"${block}\"" "${MANIFEST}" \
    | grep "\"${field}\"" \
    | head -1 \
    | sed 's/.*"'"${field}"'": *"\([^"]*\)".*/\1/'
}

FILENAME=$(parse_manifest_field "${ARCH}" "filename")
URL=$(parse_manifest_field "${ARCH}" "url")
EXPECTED_SHA256=$(parse_manifest_field "${ARCH}" "value")
SIDECAR_URL=$(grep -A 20 '"name": "winlibs_mingw GitHub' "${MANIFEST}" \
  | grep '"url"' | head -1 | sed 's/.*"url": *"\([^"]*\)".*/\1/')

DEST="${VENDOR_DIR}/${FILENAME}"

echo "============================================================"
echo " WinLibs GCC UCRT — Download Script"
echo " Arch       : ${ARCH}"
echo " File       : ${FILENAME}"
echo " Destination: ${DEST}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
mkdir -p "${VENDOR_DIR}"

if [[ -f "${DEST}" ]]; then
  echo "[INFO] File already exists: ${DEST}"
  echo "[INFO] Skipping download — will verify existing file."
else
  echo "[INFO] Downloading..."
  if command -v curl &>/dev/null; then
    curl -L --progress-bar --retry 3 --output "${DEST}" "${URL}"
  elif command -v wget &>/dev/null; then
    wget --show-progress -O "${DEST}" "${URL}"
  else
    echo "[ERROR] Neither curl nor wget found. Install one and retry." >&2
    exit 1
  fi
  echo "[INFO] Download complete."
fi

echo ""

# ---------------------------------------------------------------------------
# Verify SHA256 against manifest (pinned value)
# ---------------------------------------------------------------------------
echo "[VERIFY 1/2] Checking SHA256 against pinned manifest value..."
ACTUAL_SHA256=$(sha256sum "${DEST}" | awk '{print $1}')

if [[ "${ACTUAL_SHA256}" == "${EXPECTED_SHA256}" ]]; then
  echo "[PASS] SHA256 matches manifest."
  echo "       Expected : ${EXPECTED_SHA256}"
  echo "       Actual   : ${ACTUAL_SHA256}"
else
  echo "[FAIL] SHA256 MISMATCH against manifest!" >&2
  echo "       Expected : ${EXPECTED_SHA256}" >&2
  echo "       Actual   : ${ACTUAL_SHA256}" >&2
  echo "" >&2
  echo "[SECURITY] Deleting corrupt/tampered download." >&2
  rm -f "${DEST}"
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Cross-check SHA256 against upstream GitHub .sha256 sidecar (second source)
# ---------------------------------------------------------------------------
echo "[VERIFY 2/2] Fetching upstream .sha256 sidecar from GitHub..."
SIDECAR_TMP="$(mktemp)"
trap 'rm -f "${SIDECAR_TMP}"' EXIT

FETCH_OK=false
if command -v curl &>/dev/null; then
  if curl -fsL --retry 2 --output "${SIDECAR_TMP}" "${SIDECAR_URL}"; then
    FETCH_OK=true
  fi
elif command -v wget &>/dev/null; then
  if wget -q -O "${SIDECAR_TMP}" "${SIDECAR_URL}"; then
    FETCH_OK=true
  fi
fi

if [[ "${FETCH_OK}" == "false" ]]; then
  echo "[WARN] Could not fetch upstream sidecar — skipping cross-check."
  echo "       Manifest check (step 1) already passed; file is still usable."
else
  UPSTREAM_SHA256=$(awk '{print $1}' "${SIDECAR_TMP}")
  if [[ -z "${UPSTREAM_SHA256}" ]]; then
    echo "[WARN] Upstream sidecar was empty or unparseable — skipping cross-check."
  elif [[ "${UPSTREAM_SHA256}" == "${ACTUAL_SHA256}" ]]; then
    echo "[PASS] SHA256 matches upstream GitHub sidecar (second source confirmed)."
    echo "       Upstream : ${UPSTREAM_SHA256}"
  else
    echo "[FAIL] SHA256 MISMATCH against upstream sidecar!" >&2
    echo "       Upstream : ${UPSTREAM_SHA256}" >&2
    echo "       Actual   : ${ACTUAL_SHA256}" >&2
    echo "" >&2
    echo "[SECURITY] Manifest passed but upstream disagrees." >&2
    echo "           Investigate before using this file." >&2
    rm -f "${DEST}"
    exit 1
  fi
fi

echo ""
echo "============================================================"
echo " [SUCCESS] ${FILENAME}"
echo " Ready for air-gap transfer from:"
echo "   ${DEST}"
echo " See docs/offline-transfer.md for transfer instructions."
echo "============================================================"
