#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang-source-build/scripts/verify-clang-format-windows.sh
#
# PURPOSE: Verify the vendored pre-built clang-format.exe against the SHA256
#          pinned in manifest.json. Called automatically by bootstrap.sh on
#          Windows. Run manually to re-verify at any time.
#
#          The Windows binary (3.1 MB) fits in a single file committed
#          directly to git in bin/windows/.
#
# USAGE:
#   bash scripts/verify-clang-format-windows.sh
#
# EXIT CODES:
#   0 — binary present and SHA256 matches manifest
#   1 — binary missing or hash mismatch
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
REPO_ROOT="$(cd "${MODULE_ROOT}/../.." && pwd)"
BINARY="${REPO_ROOT}/prebuilt-binaries/toolchains/clang/clang-format.exe"

echo "============================================================"
echo " toolchains/clang-source-build — Verify clang-format.exe"
echo "============================================================"
echo ""
echo " Binary: ${BINARY}"
echo ""

# ---------------------------------------------------------------------------
# Parse expected hash from manifest
# ---------------------------------------------------------------------------
EXPECTED_HASH=""
EXPECTED_HASH=$(awk '
    /"clang_format_windows"/{found=1}
    found && /"sha256_binary"/{
        match($0, /"sha256_binary": *"([^"]+)"/, a)
        print a[1]
        exit
    }
' "${MANIFEST}")

if [[ -z "${EXPECTED_HASH}" ]]; then
    echo "[ERROR] Could not parse clang_format_windows sha256_binary from manifest.json" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Check binary exists
# ---------------------------------------------------------------------------
if [[ ! -f "${BINARY}" ]]; then
    echo "[FAIL] Binary not found: ${BINARY}" >&2
    echo "" >&2
    echo "  The vendored clang-format.exe should be committed to git." >&2
    echo "  If it is missing, re-clone the repository or check git-lfs." >&2
    echo "" >&2
    echo "  Alternatively, build from source:" >&2
    echo "    bash bootstrap.sh --build-from-source" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify SHA256
# ---------------------------------------------------------------------------
echo "[Step 1/1] Verifying SHA256..."
ACTUAL=$(sha256sum "${BINARY}" | awk '{print $1}')

echo "  Expected (manifest): ${EXPECTED_HASH}"
echo "  Actual             : ${ACTUAL}"
echo ""

if [[ "${ACTUAL}" == "${EXPECTED_HASH}" ]]; then
    chmod +x "${BINARY}"
    VER="$("${BINARY}" --version 2>/dev/null | head -1)"
    echo "[PASS] clang-format.exe integrity confirmed."
    echo ""
    echo "============================================================"
    echo " [SUCCESS] clang-format.exe is ready."
    echo " Version: ${VER}"
    echo " Binary : ${BINARY}"
    echo "============================================================"
else
    echo "[FAIL] SHA256 mismatch." >&2
    echo "  The binary may be corrupt or from a different build." >&2
    echo "" >&2
    echo "  To rebuild from source instead:" >&2
    echo "    bash bootstrap.sh --build-from-source" >&2
    exit 1
fi