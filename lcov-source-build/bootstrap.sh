#!/usr/bin/env bash
# bootstrap.sh — entry point for lcov-source-build
# Extracts vendored tarballs and verifies the installation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/vendor"

echo "=================================================================="
echo "  bootstrap.sh  —  lcov-source-build"
echo "  Repo : $SCRIPT_DIR"
echo "  Date : $(date)"
echo "=================================================================="

# ── 1. Extract lcov-2.4 ──────────────────────────────────────────────
if [[ -f "$VENDOR_DIR/lcov-2.4/bin/lcov" ]]; then
    echo "[SKIP] vendor/lcov-2.4 already extracted"
else
    echo "[INFO] Extracting lcov-2.4.tar.gz..."
    tar -xf "$VENDOR_DIR/lcov-2.4.tar.gz" -C "$VENDOR_DIR"
    echo "[DONE] lcov-2.4 extracted"
fi

# ── 2. Extract perl-libs ─────────────────────────────────────────────
if [[ -d "$VENDOR_DIR/perl-libs/lib/perl5" ]]; then
    echo "[SKIP] vendor/perl-libs already extracted"
else
    echo "[INFO] Extracting perl-libs.tar.gz..."
    tar -xf "$VENDOR_DIR/perl-libs.tar.gz" -C "$VENDOR_DIR"
    echo "[DONE] perl-libs extracted"
fi

# ── 3. Verify ────────────────────────────────────────────────────────
bash "$SCRIPT_DIR/scripts/verify.sh"
