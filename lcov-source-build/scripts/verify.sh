#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$MODULE_DIR/manifest.json"

echo "=================================================================="
echo "  verify.sh  —  lcov-source-build"
echo "  Date : $(date)"
echo "=================================================================="

# ── 1. manifest present ──────────────────────────────────────────────
if [[ ! -f "$MANIFEST" ]]; then
    echo "[FAIL] manifest.json not found at $MANIFEST"
    exit 1
fi
echo "[PASS] manifest.json found"

# ── 2. SHA256 verification ───────────────────────────────────────────
verify_sha256() {
    local label="$1"
    local file="$2"
    local expected="$3"

    if [[ ! -f "$file" ]]; then
        echo "[FAIL] $label: file not found: $file"
        return 1
    fi
    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $label SHA256 OK"
    else
        echo "[FAIL] $label SHA256 mismatch"
        echo "       expected: $expected"
        echo "       actual  : $actual"
        return 1
    fi
}

LCOV_SHA=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d['lcov_tarball']['sha256'])")
PERL_SHA=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d['perl_libs_tarball']['sha256'])")

verify_sha256 "lcov-2.4.tar.gz"   "$MODULE_DIR/vendor/lcov-2.4.tar.gz"   "$LCOV_SHA"
verify_sha256 "perl-libs.tar.gz"  "$MODULE_DIR/vendor/perl-libs.tar.gz"  "$PERL_SHA"

# ── 3. vendor dirs present ───────────────────────────────────────────
if [[ ! -f "$MODULE_DIR/vendor/lcov-2.4/bin/lcov" ]]; then
    echo "[FAIL] vendor/lcov-2.4 not extracted (run bootstrap.sh first)"
    exit 1
fi
echo "[PASS] vendor/lcov-2.4 extracted"

if [[ ! -d "$MODULE_DIR/vendor/perl-libs/lib/perl5" ]]; then
    echo "[FAIL] vendor/perl-libs not extracted (run bootstrap.sh first)"
    exit 1
fi
echo "[PASS] vendor/perl-libs extracted"

# ── 4. lcov --version ────────────────────────────────────────────────
source "$SCRIPT_DIR/env-setup.sh"
VERSION=$(lcov --version 2>&1)
if echo "$VERSION" | grep -q "LCOV version 2.4"; then
    echo "[PASS] $VERSION"
else
    echo "[FAIL] unexpected version output: $VERSION"
    exit 1
fi

echo "=================================================================="
echo "  All checks passed."
echo "=================================================================="
