#!/usr/bin/env bash
# env-setup.sh — sets up PERL5LIB and PATH for lcov 2.4
# Source this file, do not execute it directly.
#
# Usage: source lcov-source-build/scripts/env-setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"

LCOV_BIN="$MODULE_DIR/vendor/lcov-2.4/bin"
PERL_LIBS="$MODULE_DIR/vendor/perl-libs/lib/perl5"

export PATH="$LCOV_BIN:$PATH"
export PERL5LIB="$PERL_LIBS${PERL5LIB:+:$PERL5LIB}"

echo "[env-setup] lcov bin : $LCOV_BIN"
echo "[env-setup] PERL5LIB : $PERL_LIBS"
