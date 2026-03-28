#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# build-tools/lcov/scripts/env-setup.sh
#
# Activates lcov in the current shell. Source this file — do not execute.
#
# USAGE:
#   source build-tools/lcov/scripts/env-setup.sh
#
# Auto-detects the install location (admin or user path).
# Falls back to the legacy vendor/ path if nothing else is found.
# =============================================================================

_lcov_setup() {
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local MODULE_DIR
  MODULE_DIR="$(dirname "${SCRIPT_DIR}")"

  # Detect install location
  local LCOV_BIN PERL_LIBS

  # Check admin path
  if [[ -x "/opt/airgap-cpp-devkit/lcov/bin/lcov" ]]; then
    LCOV_BIN="/opt/airgap-cpp-devkit/lcov/bin"
    PERL_LIBS="/opt/airgap-cpp-devkit/lcov/lib/perl5"
  # Check user path
  elif [[ -x "${HOME}/.local/share/airgap-cpp-devkit/lcov/bin/lcov" ]]; then
    LCOV_BIN="${HOME}/.local/share/airgap-cpp-devkit/lcov/bin"
    PERL_LIBS="${HOME}/.local/share/airgap-cpp-devkit/lcov/lib/perl5"
  # Legacy fallback: vendor/ in-repo path
  elif [[ -x "${MODULE_DIR}/vendor/lcov-2.4/bin/lcov" ]]; then
    LCOV_BIN="${MODULE_DIR}/vendor/lcov-2.4/bin"
    PERL_LIBS="${MODULE_DIR}/vendor/perl-libs/lib/perl5"
    echo "[env-setup] WARNING: Using legacy in-repo lcov path." >&2
    echo "[env-setup]          Run bootstrap.sh to install properly." >&2
  else
    echo "[env-setup] ERROR: lcov not found. Run bootstrap.sh first." >&2
    return 1
  fi

  export PATH="${LCOV_BIN}:${PATH}"
  export PERL5LIB="${PERL_LIBS}${PERL5LIB:+:${PERL5LIB}}"

  echo "[env-setup] lcov bin : ${LCOV_BIN}"
  echo "[env-setup] PERL5LIB : ${PERL_LIBS}"
}
_lcov_setup
unset -f _lcov_setup
