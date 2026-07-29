#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# check-prebuilt-manifests.sh
#
# Fail if any prebuilt manifest.json declares a per-platform artifact
# (platforms.<plat>.archive or .installer) that is NOT staged — neither as a
# whole file nor as split parts. This catches the class of bug where a global
# gitignore (e.g. *.exe) silently drops a Windows installer from the submodule,
# so the manifest promises an install the UI/CLI can never deliver.
#
# SEMANTICS: presence is judged against git-TRACKED files (git ls-files), NOT
#   the working tree. A fresh clone — CI or an air-gapped bundle — only ever has
#   tracked content, so an artifact that exists on disk but was never committed
#   (e.g. blocked by a global *.exe gitignore) must fail. A working-tree-only move
#   or deletion is therefore intentionally NOT flagged; commit state is the source
#   of truth. To also guard local on-disk presence, add a separate check.
#
# USAGE:  bash scripts/internal/check-prebuilt-manifests.sh [prebuilt-dir]
# EXIT:   0 = every declared artifact is tracked; 1 = one or more missing.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREBUILT="${1:-$REPO_ROOT/prebuilt}"

PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "[!!] python3 not found on PATH" >&2; exit 1; }

if "$PY" - "$PREBUILT" <<'EOF'
import json, os, glob, sys, subprocess
root = sys.argv[1]
# Check against git-TRACKED files, not the working tree: a fresh clone (CI, an
# air-gapped bundle) only has tracked content, so an artifact that exists locally
# but was never committed (e.g. blocked by a global *.exe gitignore) must fail.
try:
    tracked = set(subprocess.check_output(['git', '-C', root, 'ls-files'], text=True).splitlines())
except Exception as e:
    print(f'ERROR: could not list tracked files in {root}: {e}')
    sys.exit(2)
missing = []
for m in glob.glob(os.path.join(root, '**', 'manifest.json'), recursive=True):
    d = os.path.dirname(m)
    try:
        j = json.load(open(m))
    except Exception:
        continue
    for k, v in (j.get('platforms') or {}).items():
        name = (v or {}).get('archive') or (v or {}).get('installer')
        if not name:
            continue
        rel = os.path.relpath(os.path.join(d, name), root).replace(os.sep, '/')
        if rel in tracked or any(t.startswith(rel + '.part-') for t in tracked):
            continue
        missing.append((os.path.relpath(m, root).replace(os.sep, '/'), k, name))
for man, k, name in sorted(missing):
    print(f'MISSING  {k:16} {name}   (declared in {man})')
sys.exit(1 if missing else 0)
EOF
then
    echo "[OK] every manifest-declared artifact is staged."
else
    echo "" >&2
    echo "[!!] Some declared artifacts are missing from prebuilt/." >&2
    echo "     Stage the file(s) above (a global *.exe gitignore is a common cause —" >&2
    echo "     prebuilt/.gitignore re-includes them, so use 'git add' after staging)," >&2
    echo "     or drop the undeliverable platform key from the manifest." >&2
    exit 1
fi
