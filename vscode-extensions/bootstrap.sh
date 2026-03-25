#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# vscode-extensions/bootstrap.sh
#
# Verifies, reassembles (if needed), and installs all vendored VS Code
# extensions into the locally installed VS Code instance.
#
# USAGE:
#   bash vscode-extensions/bootstrap.sh              # auto-detect platform
#   bash vscode-extensions/bootstrap.sh --dry-run    # verify only, no install
#   bash vscode-extensions/bootstrap.sh --verify     # verify SHA256 only
#
# REQUIREMENTS:
#   VS Code must be installed and 'code' must be on PATH (or detected below).
#   No network access required — fully offline.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="${SCRIPT_DIR}/vendor"
MANIFEST="${SCRIPT_DIR}/manifest.json"

DRY_RUN=false
VERIFY_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    DRY_RUN=true; shift ;;
        --verify)     VERIFY_ONLY=true; shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) PLATFORM="win32-x64" ;;
    Linux*)                PLATFORM="linux-x64" ;;
    Darwin*)               PLATFORM="darwin-x64" ;;
    *) echo "[ERROR] Unsupported platform." >&2; exit 1 ;;
esac

echo ""
echo "======================================================================================================"
echo "  airgap-cpp-devkit — VS Code Extensions"
echo "  Platform : ${PLATFORM}   Date : $(date '+%Y-%m-%d %H:%M:%S')"
[[ "${DRY_RUN}" == "true" ]]    && echo "  Mode     : dry-run (verify only, no install)"
[[ "${VERIFY_ONLY}" == "true" ]] && echo "  Mode     : verify SHA256 only"
echo "======================================================================================================"
echo ""

# ---------------------------------------------------------------------------
# Locate VS Code CLI
# ---------------------------------------------------------------------------
CODE_BIN=""
for candidate in \
    "$(command -v code 2>/dev/null || true)" \
    "/c/Users/${USERNAME:-${USER:-}}/AppData/Local/Programs/Microsoft VS Code/bin/code" \
    "/usr/bin/code" \
    "/usr/local/bin/code" \
    "/opt/vscode/bin/code"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
        CODE_BIN="${candidate}"
        break
    fi
done

if [[ -z "${CODE_BIN}" && "${DRY_RUN}" == "false" && "${VERIFY_ONLY}" == "false" ]]; then
    echo "[ERROR] VS Code 'code' binary not found on PATH." >&2
    echo "        Add VS Code to PATH or install it first." >&2
    echo "        On Windows: open VS Code -> Command Palette -> 'Shell Command: Install code command in PATH'" >&2
    exit 1
fi

[[ -n "${CODE_BIN}" ]] && echo "  VS Code  : ${CODE_BIN}"
echo ""

# ---------------------------------------------------------------------------
# Parse manifest — pure bash, no jq
# ---------------------------------------------------------------------------
# Returns filenames for a given platform (universal + platform-specific)
_get_extensions_for_platform() {
    local plat="$1"
    python3 - "${MANIFEST}" "${plat}" << 'PYEOF'
import json, sys
manifest = json.load(open(sys.argv[1]))
plat = sys.argv[2]
for ext in manifest["extensions"]:
    if ext["platform"] in ("universal", plat):
        print(json.dumps(ext))
PYEOF
}

# ---------------------------------------------------------------------------
# Step 1: Verify SHA256 of all parts and assembled files
# ---------------------------------------------------------------------------
echo "  [1/3] Verifying vendor files..."
echo ""

VERIFY_FAILED=false

while IFS= read -r ext_json; do
    name=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['name'])")
    version=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['version'])")
    platform=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['platform'])")
    split=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['split'])")
    filename=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['filename'])")
    sha256=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['sha256'])")

    echo "  ── ${name} ${version} (${platform})"

    if [[ "${split}" == "True" ]]; then
        # Verify parts
        parts_ok=true
        while IFS= read -r part_json; do
            part_file=$(echo "${part_json}" | python3 -c "import json,sys; p=json.loads(sys.stdin.read()); print(p['filename'])")
            part_sha=$(echo "${part_json}" | python3 -c "import json,sys; p=json.loads(sys.stdin.read()); print(p['sha256'])")
            part_path="${VENDOR_DIR}/${part_file}"
            if [[ ! -f "${part_path}" ]]; then
                echo "     [FAIL] Missing: ${part_file}"
                parts_ok=false
                VERIFY_FAILED=true
                continue
            fi
            actual=$(sha256sum "${part_path}" | awk '{print $1}')
            if [[ "${actual}" == "${part_sha}" ]]; then
                echo "     [PASS] ${part_file}"
            else
                echo "     [FAIL] ${part_file} — hash mismatch"
                parts_ok=false
                VERIFY_FAILED=true
            fi
        done < <(echo "${ext_json}" | python3 -c "
import json,sys
e=json.load(sys.stdin)
for p in e.get('parts',[]):
    print(json.dumps(p))
")
    else
        # Verify assembled file
        vsix_path="${VENDOR_DIR}/${filename}"
        if [[ ! -f "${vsix_path}" ]]; then
            echo "     [FAIL] Missing: ${filename}"
            VERIFY_FAILED=true
        else
            actual=$(sha256sum "${vsix_path}" | awk '{print $1}')
            if [[ "${actual}" == "${sha256}" ]]; then
                echo "     [PASS] ${filename}"
            else
                echo "     [FAIL] ${filename} — hash mismatch"
                VERIFY_FAILED=true
            fi
        fi
    fi
    echo ""
done < <(_get_extensions_for_platform "${PLATFORM}")

if [[ "${VERIFY_FAILED}" == "true" ]]; then
    echo "  [!!] Verification failed — aborting." >&2
    exit 1
fi

echo "  [OK]  All files verified."
echo ""

[[ "${VERIFY_ONLY}" == "true" ]] && exit 0

# ---------------------------------------------------------------------------
# Step 2: Reassemble split files
# ---------------------------------------------------------------------------
echo "  [2/3] Reassembling split extensions..."
echo ""

while IFS= read -r ext_json; do
    split=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['split'])")
    [[ "${split}" != "True" ]] && continue

    filename=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['filename'])")
    sha256=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['sha256'])")
    vsix_path="${VENDOR_DIR}/${filename}"

    if [[ -f "${vsix_path}" ]]; then
        actual=$(sha256sum "${vsix_path}" | awk '{print $1}')
        if [[ "${actual}" == "${sha256}" ]]; then
            echo "  [SKIP] Already reassembled: ${filename}"
            continue
        fi
        rm -f "${vsix_path}"
    fi

    echo "  [....] Reassembling: ${filename}"
    parts=()
    while IFS= read -r part_file; do
        part_file="${part_file//$'\r'/}"
        [[ -z "${part_file}" ]] && continue
        parts+=("${VENDOR_DIR}/${part_file}")
    done < <(echo "${ext_json}" | python3 -c "
import json,sys
e=json.load(sys.stdin)
for p in e.get('parts',[]):
    print(p['filename'])
")
    cat "${parts[@]}" > "${vsix_path}"

    actual=$(sha256sum "${vsix_path}" | awk '{print $1}')
    if [[ "${actual}" == "${sha256}" ]]; then
        echo "  [OK]   Reassembled and verified: ${filename}"
    else
        echo "  [FAIL] Reassembled hash mismatch: ${filename}" >&2
        rm -f "${vsix_path}"
        exit 1
    fi
    echo ""
done < <(_get_extensions_for_platform "${PLATFORM}")

# ---------------------------------------------------------------------------
# Step 3: Install extensions
# ---------------------------------------------------------------------------
echo "  [3/3] Installing extensions into VS Code..."
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    while IFS= read -r ext_json; do
        filename=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['filename'])")
        echo "  [dry-run] Would install: ${filename}"
    done < <(_get_extensions_for_platform "${PLATFORM}")
    echo ""
    echo "  Dry run complete."
    exit 0
fi

INSTALLED=()
FAILED=()

while IFS= read -r ext_json; do
    filename=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['filename'])")
    name=$(echo "${ext_json}" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['name'])")
    vsix_path="${VENDOR_DIR}/${filename}"

    echo "  [....] Installing: ${name} (${filename})"
    if "${CODE_BIN}" --install-extension "${vsix_path}" --force --no-sandbox --user-data-dir /tmp/vscode-airgap 2>&1 | tail -1; then
        INSTALLED+=("${name}")
        echo "  [OK]   Installed: ${name}"
    else
        FAILED+=("${name}")
        echo "  [!!]   Failed: ${name}"
    fi
    echo ""
done < <(_get_extensions_for_platform "${PLATFORM}")

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "======================================================================================================"
echo "  VS Code Extensions — Install Complete"
echo "======================================================================================================"
echo ""
for t in "${INSTALLED[@]:-}"; do [[ -n "${t}" ]] && echo "  [OK]  ${t}"; done
for t in "${FAILED[@]:-}";    do [[ -n "${t}" ]] && echo "  [!!]  ${t} (FAILED)"; done
echo ""
echo "  Reload VS Code to activate installed extensions."
echo ""