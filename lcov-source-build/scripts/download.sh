#!/usr/bin/env bash
# download.sh — run on an INTERNET-CONNECTED machine to populate vendor/
# Clones lcov 2.4 and installs Perl deps via cpanm into vendor/perl-libs,
# then tars both up and prints SHA256 hashes for manifest.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$MODULE_DIR/vendor"

echo "=================================================================="
echo "  download.sh  —  lcov-source-build"
echo "  Date : $(date)"
echo "=================================================================="

mkdir -p "$VENDOR_DIR"

# ── 1. Clone lcov 2.4 ────────────────────────────────────────────────
if [[ -d "$VENDOR_DIR/lcov-2.4" ]]; then
    echo "[SKIP] vendor/lcov-2.4 already present"
else
    echo "[INFO] Cloning lcov v2.4..."
    git clone --depth 1 --branch v2.4 \
        https://github.com/linux-test-project/lcov.git \
        "$VENDOR_DIR/lcov-2.4"
    echo "[DONE] lcov cloned"
fi

# ── 2. Install Perl deps via cpanm ───────────────────────────────────
if [[ -d "$VENDOR_DIR/perl-libs" ]]; then
    echo "[SKIP] vendor/perl-libs already present"
else
    if ! command -v cpanm &>/dev/null; then
        echo "[ERROR] cpanm not found. Install with: dnf install perl-App-cpanminus"
        exit 1
    fi
    echo "[INFO] Installing Perl dependencies..."
    cpanm --local-lib "$VENDOR_DIR/perl-libs" \
        Capture::Tiny DateTime DateTime::TimeZone
    echo "[DONE] Perl deps installed"
fi

# ── 3. Tar up ────────────────────────────────────────────────────────
echo "[INFO] Creating tarballs..."
tar -czf "$VENDOR_DIR/lcov-2.4.tar.gz"    -C "$VENDOR_DIR" lcov-2.4/
tar -czf "$VENDOR_DIR/perl-libs.tar.gz"   -C "$VENDOR_DIR" perl-libs/

echo ""
echo "Tarballs:"
ls -lh "$VENDOR_DIR/lcov-2.4.tar.gz" "$VENDOR_DIR/perl-libs.tar.gz"
echo ""
echo "SHA256 (paste into manifest.json):"
sha256sum "$VENDOR_DIR/lcov-2.4.tar.gz" "$VENDOR_DIR/perl-libs.tar.gz"
echo "=================================================================="
