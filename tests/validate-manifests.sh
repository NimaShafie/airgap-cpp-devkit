#!/usr/bin/env bash
# tests/validate-manifests.sh — static validation for the airgap-devkit repo
#
# Checks:
#   1. Shell script syntax (bash -n) for all .sh files
#   2. devkit.json  — valid JSON, required fields, valid platform values
#   3. manifest.json — valid JSON, required fields, SHA256 integrity (if archives present)
#   4. Cross-reference: every uses_prebuilt tool has a manifest.json
#
# Usage: bash tests/validate-manifests.sh [--verbose]
# Exit 0 = all passed. Exit 1 = one or more failures.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
PREBUILT_DIR="$REPO_ROOT/prebuilt"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

PASS=0; FAIL=0; SKIP=0

_pass() { PASS=$((PASS+1)); $VERBOSE && printf "    PASS  %s\n" "$1" || true; }
_fail() { FAIL=$((FAIL+1)); printf "    FAIL  %s\n" "$1"; }
_skip() { SKIP=$((SKIP+1)); $VERBOSE && printf "    SKIP  %s\n" "$1" || true; }
_section() { printf "\n── %s\n" "$1"; }
_sep()     { printf "%.0s─" {1..60}; printf "\n"; }

# Pick whichever python is available
_py() {
    if command -v python3 &>/dev/null; then python3 "$@"
    elif command -v python  &>/dev/null; then python  "$@"
    else echo "ERROR: python not found" >&2; exit 1
    fi
}

# On Windows/MINGW64, bash paths are /c/... but native Python needs C:/...
# cygpath -m converts between the two; no-op on Linux.
_pypath() {
    if command -v cygpath &>/dev/null 2>&1; then cygpath -m "$1"
    else echo "$1"
    fi
}

# _json_valid <file>  — exits 0 if valid JSON
_json_valid() {
    local p; p="$(_pypath "$1")"
    _py -c "import json,sys; json.load(open(sys.argv[1]))" "$p" 2>/dev/null
}

# _json_get <file> <key>  — prints the field value or empty string
# NOTE: no try/except — Python exits non-zero on error, bash || true gives ""
_json_get() {
    local p; p="$(_pypath "$1")"
    _py -c "
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get(sys.argv[2])
if isinstance(v, bool): print(str(v).lower())
elif v is not None:     print(str(v))
" "$p" "$2" 2>/dev/null || true
}

# _sha256_manifest <manifest_file> <archive_basename>
# Looks up the expected SHA256 from a manifest for a given file name.
_sha256_manifest() {
    local mp; mp="$(_pypath "$1")"
    _py - "$mp" "$2" <<'PYEOF' 2>/dev/null || true
import json, sys
d = json.load(open(sys.argv[1]))
name = sys.argv[2]
for plat_data in d.get("platforms", {}).values():
    if not isinstance(plat_data, dict):
        continue
    if plat_data.get("archive") == name:
        print(plat_data.get("sha256", "")); raise SystemExit
    for part in plat_data.get("parts", []):
        if isinstance(part, dict) and part.get("file") == name:
            print(part.get("sha256", "")); raise SystemExit
PYEOF
}

# _sha256_of <file>
_sha256_of() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo ""
    fi
}

_sep
printf " airgap-cpp-devkit — Manifest & Script Validator\n"
_sep

# ── 1. Shell script syntax ───────────────────────────────────────────────────
_section "1/4  Shell syntax (bash -n)"
while IFS= read -r -d '' f; do
    rel="${f#"$REPO_ROOT"/}"
    if bash -n "$f" 2>/dev/null; then
        _pass "$rel"
    else
        _fail "$rel — syntax error (run: bash -n $rel)"
    fi
done < <(find "$REPO_ROOT" \
    -not -path "*/.git/*" \
    -not -path "*/vendor/*" \
    -not -path "*/node_modules/*" \
    -name "*.sh" -print0)

# ── 2. devkit.json schema ────────────────────────────────────────────────────
_section "2/4  devkit.json — required fields & valid values"

if [[ ! -d "$TOOLS_DIR" ]]; then
    printf "    SKIP  tools/ submodule not initialised\n"
else
    DEVKIT_REQUIRED=(id name version category platform setup check_cmd)
    VALID_PLATFORMS=(windows linux both)

    while IFS= read -r -d '' f; do
        rel="${f#"$REPO_ROOT"/}"

        if ! _json_valid "$f"; then
            _fail "$rel — invalid JSON"
            continue
        fi

        tool_id="$(_json_get "$f" id)"
        label="${tool_id:-$rel}"
        all_ok=true

        for field in "${DEVKIT_REQUIRED[@]}"; do
            val="$(_json_get "$f" "$field")"
            if [[ -z "$val" ]]; then
                _fail "$label — missing required field: $field"
                all_ok=false
            fi
        done

        plat="$(_json_get "$f" platform)"
        if [[ -n "$plat" && ! " ${VALID_PLATFORMS[*]} " =~ " $plat " ]]; then
            _fail "$label — invalid platform value: '$plat' (expected: windows | linux | both)"
            all_ok=false
        fi

        $all_ok && _pass "$label"
    done < <(find "$TOOLS_DIR" -name "devkit.json" -print0)
fi

# ── 3. manifest.json schema + SHA256 integrity ───────────────────────────────
_section "3/4  manifest.json — schema & SHA256 integrity"

if [[ ! -d "$PREBUILT_DIR" ]]; then
    printf "    SKIP  prebuilt/ submodule not initialised\n"
else
    MANIFEST_REQUIRED=(tool version)

    while IFS= read -r -d '' f; do
        rel="${f#"$REPO_ROOT"/}"
        manifest_dir="$(dirname "$f")"

        if ! _json_valid "$f"; then
            _fail "$rel — invalid JSON"
            continue
        fi

        tool_id="$(_json_get "$f" tool)"
        label="${tool_id:-$rel}"
        all_ok=true

        for field in "${MANIFEST_REQUIRED[@]}"; do
            val="$(_json_get "$f" "$field")"
            if [[ -z "$val" ]]; then
                _fail "$label ($rel) — missing required field: $field"
                all_ok=false
            fi
        done

        # SHA256 verification — only when archive files are present locally.
        # Archives may be absent (air-gap delivery package); skip gracefully.
        archive_count=0
        while IFS= read -r -d '' archive; do
            archive_count=$((archive_count + 1))
            fname="$(basename "$archive")"
            expected="$(_sha256_manifest "$f" "$fname")"

            if [[ -z "$expected" ]]; then
                _skip "$label/$fname — not referenced in manifest"
                continue
            fi
            actual="$(_sha256_of "$archive")"
            if [[ -z "$actual" ]]; then
                _skip "$label/$fname — sha256sum not available on this platform"
            elif [[ "$actual" == "$expected" ]]; then
                _pass "$label/$fname — SHA256 OK"
            else
                _fail "$label/$fname — SHA256 mismatch"
                _fail "  expected: $expected"
                _fail "  actual:   $actual"
                all_ok=false
            fi
        done < <(find "$manifest_dir" -maxdepth 1 \
            \( -name "*.tar.xz" -o -name "*.zip" -o -name "*.deb" \
               -o -name "*.exe"  -o -name "*.msi" -o -name "*.part-*" \) -print0)

        if [[ $archive_count -eq 0 ]]; then
            _skip "$label — archives absent (normal for air-gap delivery)"
        else
            $all_ok && _pass "$label — manifest OK"
        fi
    done < <(find "$PREBUILT_DIR" -name "manifest.json" -print0)
fi

# ── 4. Cross-reference: uses_prebuilt tools have a manifest ─────────────────
_section "4/4  Cross-reference: uses_prebuilt=true → manifest.json present"

if [[ ! -d "$TOOLS_DIR" || ! -d "$PREBUILT_DIR" ]]; then
    printf "    SKIP  tools/ or prebuilt/ submodule not initialised\n"
else
    while IFS= read -r -d '' f; do
        uses="$(_json_get "$f" uses_prebuilt)"
        [[ "$uses" != "true" ]] && continue
        tool_id="$(_json_get "$f" id)"
        version="$(_json_get "$f" version)"
        if find "$PREBUILT_DIR" -path "*/${tool_id}/${version}/manifest.json" 2>/dev/null \
                | grep -q .; then
            _pass "$tool_id $version — manifest.json present"
        else
            _skip "$tool_id $version — manifest.json absent (may ship separately)"
        fi
    done < <(find "$TOOLS_DIR" -name "devkit.json" -print0)
fi

# ── Summary ──────────────────────────────────────────────────────────────────
_sep
printf "  PASS %-4d   FAIL %-4d   SKIP %-4d\n" "$PASS" "$FAIL" "$SKIP"
_sep
printf "\n"

[[ $FAIL -eq 0 ]]
