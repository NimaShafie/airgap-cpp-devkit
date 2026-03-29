#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${MODULE_ROOT}/../../.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
BINARY="${REPO_ROOT}/prebuilt-binaries/toolchains/clang/ninja.exe"
DEST="${MODULE_ROOT}/bin/windows/ninja.exe"

echo "============================================================"
echo " toolchains/clang-source-build — Verify ninja (Windows)"
echo "============================================================"
echo ""
echo " Binary: ${BINARY}"
echo ""

EXPECTED=$(awk '/"ninja_windows"/{f=1} f && /"sha256_binary"/{
    match($0,/"sha256_binary": *"([^"]+)"/,a); print a[1]; exit}' "${MANIFEST}")

[[ -z "${EXPECTED}" ]] && { echo "[ERROR] Could not parse sha256 from manifest" >&2; exit 1; }
[[ -f "${BINARY}" ]] || {
    echo "[FAIL] Binary not found: ${BINARY}" >&2
    echo "  Initialize the submodule: bash scripts/setup-prebuilt-submodule.sh" >&2
    exit 1
}

echo "[Step 1/1] Verifying SHA256..."
ACTUAL=$(sha256sum "${BINARY}" | awk '{print $1}')
echo "  Expected: ${EXPECTED}"
echo "  Actual  : ${ACTUAL}"
echo ""

if [[ "${ACTUAL}" == "${EXPECTED}" ]]; then
    mkdir -p "$(dirname "${DEST}")"
    cp -f "${BINARY}" "${DEST}"
    chmod +x "${DEST}"
    VER="$("${DEST}" --version 2>/dev/null | head -1)"
    echo "[PASS] ninja integrity confirmed."
    echo "============================================================"
    echo " [SUCCESS] ninja is ready."
    echo " Version: ${VER}"
    echo " Binary : ${DEST}"
    echo "============================================================"
else
    echo "[FAIL] SHA256 mismatch." >&2
    exit 1
fi
