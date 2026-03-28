#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# toolchains/clang-source-build/scripts/reassemble-clang-tidy.sh
#
# PURPOSE: Verify each clang-tidy split part, reassemble them into the
#          pre-built binary, then verify the binary against the SHA256
#          pinned in manifest.json.
#
#          clang-tidy is a large binary (~84 MB) committed as split parts
#          to stay under git hosting file size limits (100 MB max).
#          The parts are in bin/linux/:
#            clang-tidy.part-aa  (~52 MB)
#            clang-tidy.part-ab  (~31 MB)
#
#          This script is called automatically by bootstrap.sh on Linux.
#          Run it manually if you only need clang-tidy without rebuilding
#          clang-format.
#
# USAGE:
#   bash scripts/reassemble-clang-tidy.sh
#
# EXIT CODES:
#   0 — reassembly succeeded, all hashes match
#   1 — any hash mismatch or missing part
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
REPO_ROOT="$(cd "${MODULE_ROOT}/../../.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/clang/source-build"
BIN_DIR="${MODULE_ROOT}/bin/linux"
mkdir -p "${BIN_DIR}"

echo "============================================================"
echo " toolchains/clang-source-build — Reassemble clang-tidy"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Manifest parsing helpers (clang_tidy block)
# ---------------------------------------------------------------------------

get_tidy_binary_filename() {
    # Returns the value of "binary_filename" under the clang_tidy block,
    # The manifest stores only the basename (e.g. clang-tidy.part-aa).
    awk '/"clang_tidy_linux"/{found=1} found && /"binary_filename"/{
        match($0, /"binary_filename": *"([^"]+)"/, a)
        n = split(a[1], parts, "/")
        print parts[n]
        exit
    }' "${MANIFEST}"
}

get_tidy_binary_hash() {
    awk '/"clang_tidy_linux"/{found=1} found && /"sha256_binary"/{
        match($0, /"sha256_binary": *"([^"]+)"/, a); print a[1]; exit
    }' "${MANIFEST}"
}

get_tidy_part_filenames() {
    # Returns only the basename of each part filename under clang_tidy.
    # The manifest stores them as "bin/linux/clang-tidy.part-xx".
    awk '
        /"clang_tidy_linux"/{intidy=1}
        intidy && /"split_parts"/{inparts=1}
        inparts && /"filename"/{
            match($0, /"filename": *"([^"]+)"/, a)
            n = split(a[1], parts, "/")
            print parts[n]
        }
        inparts && /^\s*\]/{inparts=0; intidy=0}
    ' "${MANIFEST}"
}

get_tidy_part_hash() {
    local part_basename="$1"
    # The manifest uses the full path as the key value; match on basename.
    awk -v target="${part_basename}" '
        /"clang_tidy_linux"/{intidy=1}
        intidy && index($0, target) && /"filename"/{found=1; next}
        found && /"sha256"/{
            match($0, /"sha256": *"([^"]+)"/, a); print a[1]; exit
        }
    ' "${MANIFEST}"
}

# ---------------------------------------------------------------------------
# Parse manifest values
# ---------------------------------------------------------------------------
TIDY_BINARY=$(get_tidy_binary_filename)
TIDY_HASH=$(get_tidy_binary_hash)
OUTPUT="${BIN_DIR}/${TIDY_BINARY}"

if [[ -z "${TIDY_BINARY}" ]]; then
    echo "[ERROR] Could not parse clang_tidy binary_filename from manifest.json" >&2; exit 1
fi
if [[ -z "${TIDY_HASH}" ]]; then
    echo "[ERROR] Could not parse clang_tidy sha256_binary from manifest.json" >&2; exit 1
fi

echo " Output: ${OUTPUT}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify each part
# ---------------------------------------------------------------------------
echo "[STEP 1/3] Verifying split parts..."

PARTS=()
ALL_OK=true

while IFS= read -r part_basename; do
    [[ -z "${part_basename}" ]] && continue
    part_path="${PREBUILT_DIR}/${part_basename}"
    expected_hash=$(get_tidy_part_hash "${part_basename}")

    if [[ -z "${expected_hash}" ]]; then
        echo "  [FAIL] Could not find hash for ${part_basename} in manifest.json" >&2
        ALL_OK=false
        continue
    fi

    if [[ ! -f "${part_path}" ]]; then
        echo "  [FAIL] Missing: ${part_basename}" >&2
        ALL_OK=false
        continue
    fi

    actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')

    if [[ "${actual_hash}" == "${expected_hash}" ]]; then
        echo "  [PASS] ${part_basename}"
        PARTS+=("${part_path}")
    else
        echo "  [FAIL] ${part_basename}" >&2
        echo "         Expected : ${expected_hash}" >&2
        echo "         Actual   : ${actual_hash}" >&2
        ALL_OK=false
    fi
done < <(get_tidy_part_filenames)

if [[ "${ALL_OK}" == "false" ]]; then
    echo "" >&2
    echo "[ABORT] Part verification failed. Cannot reassemble." >&2
    exit 1
fi

if [[ "${#PARTS[@]}" -eq 0 ]]; then
    echo "  [FAIL] No clang-tidy parts found in ${BIN_DIR}/" >&2
    exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Reassemble
# ---------------------------------------------------------------------------
echo "[STEP 2/3] Reassembling ${#PARTS[@]} parts into ${TIDY_BINARY}..."

rm -f "${OUTPUT}"
cat "${PARTS[@]}" > "${OUTPUT}"
chmod +x "${OUTPUT}"

echo "[INFO] Done. Size: $(du -h "${OUTPUT}" | awk '{print $1}')"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Verify reassembled binary
# ---------------------------------------------------------------------------
echo "[STEP 3/3] Verifying reassembled binary SHA256..."
ACTUAL=$(sha256sum "${OUTPUT}" | awk '{print $1}')

echo "  Expected (manifest): ${TIDY_HASH}"
echo "  Actual             : ${ACTUAL}"
echo ""

if [[ "${ACTUAL}" == "${TIDY_HASH}" ]]; then
    echo "[PASS] clang-tidy binary integrity confirmed."
    echo ""
    echo "============================================================"
    echo " [SUCCESS] clang-tidy is ready."
    echo " Binary: ${OUTPUT}"
    echo " Run 'clang-tidy --version' to confirm."
    echo "============================================================"
else
    echo "[FAIL] clang-tidy binary hash mismatch." >&2
    echo "       Parts passed individually but assembled file is wrong." >&2
    rm -f "${OUTPUT}"
    exit 1
fi