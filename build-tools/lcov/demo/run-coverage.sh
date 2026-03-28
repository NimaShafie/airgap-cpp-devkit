#!/usr/bin/env bash
# run-coverage.sh — full coverage workflow for the lcov demo
# Usage: bash run-coverage.sh
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$DEMO_DIR")"

# ── Activate lcov environment ────────────────────────────────────────
source "$MODULE_DIR/scripts/env-setup.sh"

echo "=================================================================="
echo "  run-coverage.sh  —  lcov demo"
echo "  Date : $(date)"
echo "=================================================================="

cd "$DEMO_DIR"

# ── 1. Clean previous build ──────────────────────────────────────────
echo "[1/5] Cleaning previous build..."
rm -f test_math *.gcda *.gcno src/*.gcda src/*.gcno tests/*.gcda tests/*.gcno
rm -f coverage.info coverage_filtered.info
rm -rf coverage-report/

# ── 2. Compile with coverage flags ───────────────────────────────────
echo "[2/5] Compiling with coverage flags..."
g++ -fprofile-arcs -ftest-coverage -g \
    src/math.cpp tests/test_math.cpp -o test_math

# ── 3. Run tests ─────────────────────────────────────────────────────
echo "[3/5] Running tests..."
./test_math

# ── 4. Capture coverage ──────────────────────────────────────────────
echo "[4/5] Capturing coverage data..."
lcov --capture \
     --directory . \
     --output-file coverage.info \
     --gcov-tool gcov \
     --ignore-errors mismatch

lcov --remove coverage.info '/usr/*' \
     --output-file coverage_filtered.info \
     --ignore-errors unused,unused

# ── 5. Generate HTML report ──────────────────────────────────────────
echo "[5/5] Generating HTML report..."
genhtml coverage_filtered.info \
        --output-directory coverage-report \
        --title "lcov demo - math library"

echo ""
echo "=================================================================="
lcov --summary coverage_filtered.info
echo ""
echo "  HTML report : $DEMO_DIR/coverage-report/index.html"
echo "=================================================================="
