#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# check-setup-exit-traps.sh
#
# Fail if any tool setup.sh installs a bare `trap ... EXIT`. The shared library
# (tools/lib/devkit-install.sh) owns the single EXIT handler that runs a
# composable cleanup registry; a bare `trap ... EXIT` in a setup.sh REPLACES it,
# silently disarming the library's temp-root cleanup and leaking /tmp. setup.sh
# scripts must register on-exit cleanup with devkit_add_exit_trap instead.
#
# The library's own registry handler lives in devkit-install.sh (not a setup.sh),
# so scoping the scan to setup.sh files keeps it out of scope automatically.
#
# USAGE:  bash scripts/internal/check-setup-exit-traps.sh [tools-dir]
# EXIT:   0 = no bare EXIT traps; 1 = one or more found.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLS="${1:-$REPO_ROOT/tools}"

# Match a real `trap ... EXIT` STATEMENT (leading whitespace only) — not a `#`
# comment, and not the devkit_add_exit_trap helper. EXIT is matched as a signal
# token so `trap '...' EXIT INT TERM` is caught too.
PATTERN='^[[:space:]]*trap[[:space:]].*[[:space:]]EXIT([[:space:]]|$)'

matches="$(grep -rnE --include='setup.sh' "$PATTERN" "$TOOLS" 2>/dev/null \
    | grep -v 'devkit_add_exit_trap' || true)"

if [[ -n "$matches" ]]; then
    echo "$matches" | sed "s#^${REPO_ROOT}/##; s/^/BARE-EXIT-TRAP  /"
    echo "" >&2
    echo "[!!] A setup.sh installs a bare 'trap ... EXIT', which replaces the" >&2
    echo "     library's cleanup registry and leaks its temp-root. Register the" >&2
    echo "     cleanup with devkit_add_exit_trap '...' instead." >&2
    exit 1
fi

echo "[OK] no bare 'trap ... EXIT' in tool setup.sh scripts."
