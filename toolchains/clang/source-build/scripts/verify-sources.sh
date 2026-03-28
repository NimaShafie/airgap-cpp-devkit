#!/usr/bin/env bash
# =============================================================================
# toolchains/clang-source-build/scripts/verify-sources.sh
#
# PURPOSE: Offline SHA256 verification of all vendored archives and binaries.
#          Checks:
#            • LLVM split parts (or reassembled tarball if present)
#            • Ninja source tarball
#            • clang-tidy pre-built binary parts (Linux only)
#
#          No network access required.
#
# USAGE:
#   bash scripts/verify-sources.sh
#
# EXIT CODES:
#   0 - all checks passed
#   1 - any mismatch or missing file
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
LLVM_SRC="${MODULE_ROOT}/llvm-src"
NINJA_SRC="${MODULE_ROOT}/ninja-src"
REPO_ROOT="$(cd "${MODULE_ROOT}/../.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/toolchains/clang"
BIN_LINUX="${MODULE_ROOT}/bin/linux"

echo "============================================================"
echo " toolchains/clang-source-build -- Source & Binary Verification"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Manifest parsing helpers — LLVM
# ---------------------------------------------------------------------------

get_llvm_tarball() {
    grep '"tarball_filename"' "${MANIFEST}" | head -1 \
        | sed 's/.*"tarball_filename": *"\([^"]*\)".*/\1/' || true
}

get_llvm_reassembled_hash() {
    grep -A 3 '"sha256_reassembled"' "${MANIFEST}" \
        | grep '"value"' | head -1 \
        | sed 's/.*"value": *"\([^"]*\)".*/\1/' || true
}

get_llvm_part_filenames() {
    grep '"filename".*part-' "${MANIFEST}" \
        | grep -v 'clang-tidy' \
        | sed 's/.*"filename": *"\([^"]*\)".*/\1/' || true
}

get_llvm_part_hash() {
    local part_filename="$1"
    grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
        | grep '"sha256"' \
        | sed 's/.*"sha256": *"\([^"]*\)".*/\1/' || true
}

# ---------------------------------------------------------------------------
# Manifest parsing helpers — Ninja
# ---------------------------------------------------------------------------

get_ninja_tarball() {
    awk '/"ninja"/{found=1} found && /"tarball_filename"/{
        match($0, /"tarball_filename": *"([^"]+)"/, a); print a[1]; exit
    }' "${MANIFEST}" || true
}

get_ninja_hash() {
    awk '/"ninja"/{found=1} found && /"value"/{
        match($0, /"value": *"([^"]+)"/, a); print a[1]; exit
    }' "${MANIFEST}" || true
}

# ---------------------------------------------------------------------------
# Manifest parsing helpers — clang-tidy
# ---------------------------------------------------------------------------

get_tidy_binary_hash() {
    awk '/"clang_tidy_linux"/{found=1} found && /"sha256_binary"/{
        match($0, /"sha256_binary": *"([^"]+)"/, a); print a[1]; exit
    }' "${MANIFEST}" || true
}

get_tidy_part_filenames() {
    awk '
        /"clang_tidy_linux"/{intidy=1}
        intidy && /"split_parts"/{inparts=1}
        inparts && /"filename"/{
            match($0, /"filename": *"([^"]+)"/, a)
            n = split(a[1], parts, "/")
            print parts[n]
        }
        inparts && /^\s*\]/{inparts=0; intidy=0}
    ' "${MANIFEST}" || true
}

get_tidy_part_hash() {
    local part_basename="$1"
    awk -v target="${part_basename}" '
        /"clang_tidy_linux"/{intidy=1}
        intidy && index($0, target) && /"filename"/{found=1; next}
        found && /"sha256"/{
            match($0, /"sha256": *"([^"]+)"/, a); print a[1]; exit
        }
    ' "${MANIFEST}" || true
}

# ---------------------------------------------------------------------------
# Parse and validate manifest keys
# ---------------------------------------------------------------------------
LLVM_TARBALL=$(get_llvm_tarball)
LLVM_REASSEMBLED_HASH=$(get_llvm_reassembled_hash)
NINJA_TARBALL=$(get_ninja_tarball)
NINJA_HASH=$(get_ninja_hash)

[[ -z "${LLVM_TARBALL}" ]]          && { echo "[ERROR] Could not parse LLVM tarball_filename from manifest.json" >&2; exit 1; }
[[ -z "${LLVM_REASSEMBLED_HASH}" ]] && { echo "[ERROR] Could not parse LLVM sha256_reassembled value from manifest.json" >&2; exit 1; }
[[ -z "${NINJA_TARBALL}" ]]         && { echo "[ERROR] Could not parse Ninja tarball_filename from manifest.json" >&2; exit 1; }
[[ -z "${NINJA_HASH}" ]]            && { echo "[ERROR] Could not parse Ninja sha256 value from manifest.json" >&2; exit 1; }

ALL_OK=true

# ---------------------------------------------------------------------------
# LLVM
# ---------------------------------------------------------------------------
echo "[LLVM] Checking source archive..."
LLVM_ASSEMBLED="${LLVM_SRC}/${LLVM_TARBALL}"

if [[ -f "${LLVM_ASSEMBLED}" ]]; then
    echo "[MODE] Reassembled tarball found -- verifying directly."
    echo "       File: ${LLVM_ASSEMBLED}"
    ACTUAL=$(sha256sum "${LLVM_ASSEMBLED}" | awk '{print $1}')
    echo "  Expected (manifest): ${LLVM_REASSEMBLED_HASH}"
    echo "  Actual             : ${ACTUAL}"
    if [[ "${ACTUAL}" == "${LLVM_REASSEMBLED_HASH}" ]]; then
        echo "  [PASS] LLVM tarball integrity confirmed."
    else
        echo "  [FAIL] LLVM tarball hash mismatch." >&2
        ALL_OK=false
    fi
else
    echo "[MODE] No reassembled tarball -- verifying split parts."
    FOUND=0
    while IFS= read -r part_filename; do
        [[ -z "${part_filename}" ]] && continue
        part_path="${LLVM_SRC}/${part_filename}"
        expected_hash=$(get_llvm_part_hash "${part_filename}")
        if [[ ! -f "${part_path}" ]]; then
            echo "  [FAIL] Missing: ${part_filename}" >&2
            ALL_OK=false
            continue
        fi
        actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')
        FOUND=$((FOUND + 1))
        if [[ "${actual_hash}" == "${expected_hash}" ]]; then
            echo "  [PASS] ${part_filename}"
        else
            echo "  [FAIL] ${part_filename}" >&2
            echo "         Expected : ${expected_hash}" >&2
            echo "         Actual   : ${actual_hash}" >&2
            ALL_OK=false
        fi
    done < <(get_llvm_part_filenames)

    if [[ "${FOUND}" -eq 0 ]]; then
        echo "  [FAIL] No LLVM parts found in llvm-src/." >&2
        ALL_OK=false
    elif [[ "${ALL_OK}" == "true" ]]; then
        echo "  [INFO] All ${FOUND} parts verified."
        echo "         Next: bash scripts/reassemble-llvm.sh"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Ninja
# ---------------------------------------------------------------------------
echo "[Ninja] Checking source tarball..."
NINJA_PATH="${NINJA_SRC}/${NINJA_TARBALL}"

if [[ ! -f "${NINJA_PATH}" ]]; then
    echo "  [FAIL] Missing: ${NINJA_PATH}" >&2
    ALL_OK=false
else
    ACTUAL=$(sha256sum "${NINJA_PATH}" | awk '{print $1}')
    echo "  Expected (manifest): ${NINJA_HASH}"
    echo "  Actual             : ${ACTUAL}"
    if [[ "${ACTUAL}" == "${NINJA_HASH}" ]]; then
        echo "  [PASS] Ninja tarball integrity confirmed."
    else
        echo "  [FAIL] Ninja tarball hash mismatch." >&2
        ALL_OK=false
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# clang-tidy pre-built binary parts (Linux only)
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    Linux*)
        echo "[clang-tidy] Checking pre-built binary parts..."
        TIDY_BINARY_HASH=$(get_tidy_binary_hash)
        TIDY_ASSEMBLED="${BIN_LINUX}/clang-tidy"
        FOUND=0
        TIDY_OK=true

        if [[ -f "${TIDY_ASSEMBLED}" ]]; then
            echo "[MODE] Assembled binary found -- verifying directly."
            echo "       File: ${TIDY_ASSEMBLED}"
            ACTUAL=$(sha256sum "${TIDY_ASSEMBLED}" | awk '{print $1}')
            echo "  Expected (manifest): ${TIDY_BINARY_HASH}"
            echo "  Actual             : ${ACTUAL}"
            if [[ "${ACTUAL}" == "${TIDY_BINARY_HASH}" ]]; then
                echo "  [PASS] clang-tidy binary integrity confirmed."
            else
                echo "  [FAIL] clang-tidy binary hash mismatch." >&2
                ALL_OK=false
            fi
        else
            echo "[MODE] No assembled binary -- verifying split parts."
            while IFS= read -r part_basename; do
                [[ -z "${part_basename}" ]] && continue
                part_path="${BIN_LINUX}/${part_basename}"
                expected_hash=$(get_tidy_part_hash "${part_basename}")
                if [[ ! -f "${part_path}" ]]; then
                    echo "  [FAIL] Missing: ${part_basename}" >&2
                    ALL_OK=false
                    TIDY_OK=false
                    continue
                fi
                actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')
                FOUND=$((FOUND + 1))
                if [[ "${actual_hash}" == "${expected_hash}" ]]; then
                    echo "  [PASS] ${part_basename}"
                else
                    echo "  [FAIL] ${part_basename}" >&2
                    echo "         Expected : ${expected_hash}" >&2
                    echo "         Actual   : ${actual_hash}" >&2
                    ALL_OK=false
                    TIDY_OK=false
                fi
            done < <(get_tidy_part_filenames)

            if [[ "${FOUND}" -eq 0 ]]; then
                echo "  [FAIL] No clang-tidy parts found in bin/linux/." >&2
                ALL_OK=false
            elif [[ "${TIDY_OK}" == "true" ]]; then
                echo "  [INFO] All ${FOUND} parts verified."
                echo "         Next: bash scripts/reassemble-clang-tidy.sh"
            fi
        fi
        echo ""
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "[clang-format] Checking pre-built Windows binary..."
        FMT_BINARY="${PREBUILT_DIR}/clang-format.exe"
        FMT_HASH=$(awk '
            /"clang_format_windows"/{found=1}
            found && /"sha256_binary"/{
                match($0, /"sha256_binary": *"([^"]+)"/, a); print a[1]; exit
            }
        ' "${MANIFEST}" || true)

        if [[ ! -f "${FMT_BINARY}" ]]; then
            echo "  [FAIL] Missing: ${FMT_BINARY}" >&2
            ALL_OK=false
        elif [[ -z "${FMT_HASH}" ]]; then
            echo "  [FAIL] Could not parse clang_format_windows sha256_binary from manifest.json" >&2
            ALL_OK=false
        else
            ACTUAL=$(sha256sum "${FMT_BINARY}" | awk '{print $1}')
            echo "  Expected (manifest): ${FMT_HASH}"
            echo "  Actual             : ${ACTUAL}"
            if [[ "${ACTUAL}" == "${FMT_HASH}" ]]; then
                echo "  [PASS] clang-format.exe integrity confirmed."
            else
                echo "  [FAIL] clang-format.exe hash mismatch." >&2
                ALL_OK=false
            fi
        fi
        echo ""

        echo "[clang-tidy] Checking pre-built Windows binary..."
        WIN_BINARY="${PREBUILT_DIR}/clang-tidy.exe"
        WIN_HASH=$(awk '
            /"clang_tidy_windows"/{found=1}
            found && /"sha256_binary"/{
                match($0, /"sha256_binary": *"([^"]+)"/, a); print a[1]; exit
            }
        ' "${MANIFEST}" || true)

        if [[ ! -f "${WIN_BINARY}" ]]; then
            echo "  [FAIL] Missing: ${WIN_BINARY}" >&2
            ALL_OK=false
        elif [[ -z "${WIN_HASH}" ]]; then
            echo "  [FAIL] Could not parse clang_tidy_windows sha256_binary from manifest.json" >&2
            ALL_OK=false
        else
            ACTUAL=$(sha256sum "${WIN_BINARY}" | awk '{print $1}')
            echo "  Expected (manifest): ${WIN_HASH}"
            echo "  Actual             : ${ACTUAL}"
            if [[ "${ACTUAL}" == "${WIN_HASH}" ]]; then
                echo "  [PASS] clang-tidy.exe integrity confirmed."
            else
                echo "  [FAIL] clang-tidy.exe hash mismatch." >&2
                ALL_OK=false
            fi
        fi
        echo ""
        ;;
    *)
        echo "[clang-tidy] Skipped — no pre-built binary for this platform."
        echo ""
        ;;
esac

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ "${ALL_OK}" == "true" ]]; then
    echo "[PASS] All archives and binaries verified."
    exit 0
else
    echo "[FAIL] One or more items failed verification." >&2
    exit 1
fi