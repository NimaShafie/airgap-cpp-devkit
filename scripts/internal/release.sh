#!/usr/bin/env bash
# Release script — bumps version, builds Go binaries, builds pip wheel,
# creates a GitHub release, and publishes to PyPI.
#
# Usage:
#   bash scripts/internal/release.sh <version> [flags]
#
# Flags:
#   --no-build        Skip Go compile (use existing prebuilt/ binaries)
#   --upload          Publish wheel + sdist to PyPI (real index)
#   --test            Publish to TestPyPI instead of real PyPI (implies --upload)
#   --skip-sign       Skip Authenticode / GPG binary signing
#   --skip-vt         Skip VirusTotal scan
#   --skip-gh-release Skip creating the GitHub release and tag
#
# Standard full release (new binaries, public):
#   bash scripts/internal/release.sh 1.2.3 --upload
#
# Hotfix / bug-fix only (binaries unchanged):
#   bash scripts/internal/release.sh 1.2.3 --no-build --skip-sign --skip-vt --upload
#
# Dry run (local build only, no publish):
#   bash scripts/internal/release.sh 1.2.3 --no-build --skip-sign --skip-vt --skip-gh-release
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── args ──────────────────────────────────────────────────────────────────────
VERSION="${1:-}"
NO_BUILD=false
UPLOAD=false
TEST_PYPI=false
SKIP_SIGN=false
SKIP_VT=false
SKIP_GH_RELEASE=false

if [[ -z "$VERSION" ]]; then
    echo "Usage: bash scripts/internal/release.sh <version> [--no-build] [--upload] [--test] [--skip-sign] [--skip-vt] [--skip-gh-release]" >&2
    echo "  version format: 1.2.3 or 1.2.3rc1 or 1.2.3b2" >&2
    exit 1
fi

shift
for arg in "$@"; do
    case "$arg" in
        --no-build)       NO_BUILD=true ;;
        --upload)         UPLOAD=true ;;
        --test)           TEST_PYPI=true; UPLOAD=true ;;
        --skip-sign)      SKIP_SIGN=true ;;
        --skip-vt)        SKIP_VT=true ;;
        --skip-gh-release) SKIP_GH_RELEASE=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# ── python detection ──────────────────────────────────────────────────────────
# Find a Python that has 'build' and 'twine' installed.
PYTHON=""
for candidate in \
    "$HOME/AppData/Local/Python/pythoncore-3.14-64/python.exe" \
    "python3" "python"; do
    if "$candidate" -c "import build, twine" 2>/dev/null; then
        PYTHON="$candidate"
        break
    fi
done

if [[ -z "$PYTHON" ]]; then
    echo "ERROR: No Python found with 'build' and 'twine' installed." >&2
    echo "Run: pip install build twine" >&2
    exit 1
fi
echo "Python: $PYTHON ($($PYTHON --version))"

# ── validate version ──────────────────────────────────────────────────────────
# PEP 440: 1.2.3 / 1.2.3rc1 / 1.2.3b2 / 1.2.3a1
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(a|b|rc)[0-9]+$|^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: invalid version '$VERSION'. Use PEP 440 format: 1.2.3 or 1.2.3rc1" >&2
    exit 1
fi

# go version.go uses dashes (1.0.1-rc.2); pip uses no-dash (1.0.1rc2)
# Derive the Go-style version for version.go from the PEP 440 string
GO_VERSION="$VERSION"
if echo "$VERSION" | grep -qE '(a|b|rc)[0-9]+$'; then
    # 1.0.2rc1 → 1.0.2-rc.1  |  1.0.2b2 → 1.0.2-beta.2  |  1.0.2a1 → 1.0.2-alpha.1
    GO_VERSION=$(echo "$VERSION" | sed -E \
        -e 's/([0-9]+)rc([0-9]+)$/\1-rc.\2/' \
        -e 's/([0-9]+)b([0-9]+)$/\1-beta.\2/' \
        -e 's/([0-9]+)a([0-9]+)$/\1-alpha.\2/')
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Version bump"
echo "    PEP 440 (pip):  $VERSION"
echo "    Go (server):    $GO_VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Escape for use as a sed replacement string (guards / \ & against any future
# version-format changes that might introduce these characters).
_sed_escape() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
VERSION_ESC="$(_sed_escape "$VERSION")"
GO_VERSION_ESC="$(_sed_escape "$GO_VERSION")"

# ── 1. bump version.go ────────────────────────────────────────────────────────
VERSION_GO="$REPO_ROOT/server/internal/api/version.go"
sed -i "s/const AppVersion = \".*\"/const AppVersion = \"$GO_VERSION_ESC\"/" "$VERSION_GO"
echo "  bumped $VERSION_GO → $GO_VERSION"

# ── 2. bump pyproject.toml ────────────────────────────────────────────────────
PYPROJECT="$REPO_ROOT/packages/python/pyproject.toml"
sed -i "s/^version = \".*\"/version = \"$VERSION_ESC\"/" "$PYPROJECT"
echo "  bumped $PYPROJECT → $VERSION"

# ── 3. bump __init__.py ───────────────────────────────────────────────────────
INIT_PY="$REPO_ROOT/packages/python/src/airgap_devkit/__init__.py"
sed -i "s/__version__ = \".*\"/__version__ = \"$VERSION_ESC\"/" "$INIT_PY"
echo "  bumped $INIT_PY → $VERSION"

# ── 4. build Go binaries ──────────────────────────────────────────────────────
if [[ "$NO_BUILD" == false ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building Go binaries"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "$REPO_ROOT/scripts/internal/build-server.sh"
else
    echo "  --no-build: skipping Go compile, using existing prebuilt/"
fi

# ── 4b. sign binaries ─────────────────────────────────────────────────────────
if [[ "$SKIP_SIGN" == false ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Code signing"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "$REPO_ROOT/scripts/internal/sign-binaries.sh"
else
    echo "  --skip-sign: skipping binary signing"
fi

# ── 4c. VirusTotal scan ────────────────────────────────────────────────────────
if [[ "$SKIP_VT" == false ]]; then
    if [[ -z "${VT_API_KEY:-}" ]]; then
        echo ""
        echo "  [WARN] VT_API_KEY not set — skipping VirusTotal scan"
        echo "         To scan: export VT_API_KEY=<key> and re-run, or use --skip-vt to suppress this warning"
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  VirusTotal scan"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        bash "$REPO_ROOT/scripts/internal/virustotal-scan.sh" \
            "$REPO_ROOT/prebuilt/bin/devkit-server-linux-amd64" \
            "$REPO_ROOT/prebuilt/bin/devkit-server-windows-amd64.exe"
    fi
else
    echo "  --skip-vt: skipping VirusTotal scan"
fi

# ── 4d. commit & push prebuilt submodule ──────────────────────────────────────
# Must happen before the parent repo is updated so CI can always fetch the pointer.
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Syncing prebuilt submodule to remote"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
(
    cd "$REPO_ROOT/prebuilt"
    if [[ "$NO_BUILD" == false ]]; then
        git add bin/
        if ! git diff --staged --quiet; then
            git commit -m "chore: v$GO_VERSION binaries"
            echo "  Committed new server binaries to prebuilt"
        fi
    fi
    pending=$(git log --oneline "origin/main..HEAD" 2>/dev/null | wc -l | tr -d '[:space:]')
    if [[ "$pending" -gt 0 ]]; then
        echo "  Pushing $pending unpushed commit(s) to prebuilt origin/main ..."
        git push origin main
        echo "  Pushed prebuilt → origin/main"
    else
        echo "  prebuilt already up to date with origin/main"
    fi
)

# ── 5. stage binaries ─────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Staging binaries"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$REPO_ROOT/packages/python/scripts/stage-binaries.sh"

# ── 6. build wheel ────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building wheel"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
rm -rf "$REPO_ROOT/dist/python/"
"$PYTHON" -m build "$REPO_ROOT/packages/python/" --outdir "$REPO_ROOT/dist/python/"

WHEEL=$(ls "$REPO_ROOT/dist/python/"*.whl 2>/dev/null | head -1)
echo ""
echo "  Built: $WHEEL"
echo "  Size:  $(du -h "$WHEEL" | cut -f1)"

# ── 7. check ──────────────────────────────────────────────────────────────────
echo ""
echo "  Checking with twine..."
"$PYTHON" -m twine check "$REPO_ROOT/dist/python/"*

# ── 8. GitHub release ─────────────────────────────────────────────────────────
# Creates a git tag, pushes it, and publishes a GitHub release with the wheel
# and sdist attached.  Skipped for pre-release versions (a/b/rc) by default
# unless the caller explicitly passes --upload (or a full stable version).
if [[ "$SKIP_GH_RELEASE" == false ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  GitHub release"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ! command -v gh &>/dev/null; then
        echo "  [WARN] 'gh' CLI not found — skipping GitHub release."
        echo "         Install gh (https://cli.github.com/) and re-run, or use --skip-gh-release."
    else
        TAG="v$GO_VERSION"

        # Push the working-tree commit before tagging so the tag lands on the
        # version-bumped commit (not the commit before it).
        echo "  Pushing main branch..."
        git -C "$REPO_ROOT" push origin main

        # Create + push the tag (skip if it already exists on the remote).
        if git -C "$REPO_ROOT" ls-remote --exit-code --tags origin "$TAG" &>/dev/null; then
            echo "  Tag $TAG already exists on remote — skipping tag push."
        else
            git -C "$REPO_ROOT" tag "$TAG"
            git -C "$REPO_ROOT" push origin "$TAG"
            echo "  Pushed tag $TAG"
        fi

        # Build the release notes from the CHANGELOG block for this version.
        # Print the body between this version's "## [ver]" header and the next
        # "## [" header, excluding both headers, section-separator "---" lines,
        # and leading/trailing blank lines. A plain awk range (/start/,/end/)
        # fails here because the start line also matches the end pattern, which
        # collapses the range to the header line alone.
        _changelog_section() {
            local ver="$1" cl="$REPO_ROOT/CHANGELOG.md"
            awk -v ver="$ver" '
                index($0, "## [" ver "]") == 1 { f = 1; next }
                f && /^## \[/                  { exit }
                f && $0 == "---"               { next }
                f { buf[n++] = $0 }
                END {
                    i = 0;     while (i < n && buf[i] ~ /^[[:space:]]*$/) i++
                    j = n - 1; while (j >= i && buf[j] ~ /^[[:space:]]*$/) j--
                    for (k = i; k <= j; k++) print buf[k]
                }
            ' "$cl"
        }
        RELEASE_NOTES="$(_changelog_section "$VERSION")"
        if [[ -z "$RELEASE_NOTES" ]]; then
            RELEASE_NOTES="See [CHANGELOG.md](CHANGELOG.md) for details."
        fi
        # Append install snippet
        RELEASE_NOTES="${RELEASE_NOTES}

## Install

\`\`\`
pip install airgap-devkit==$VERSION
\`\`\`"

        SDIST=$(ls "$REPO_ROOT/dist/python/"*.tar.gz 2>/dev/null | head -1)
        WHEEL_FILE=$(ls "$REPO_ROOT/dist/python/"*.whl 2>/dev/null | head -1)

        GH_FLAGS=(--title "v${GO_VERSION}" --notes "$RELEASE_NOTES" --latest)
        # Pre-release versions (a/b/rc in PEP 440) get --prerelease flag
        if echo "$VERSION" | grep -qE '(a|b|rc)[0-9]+$'; then
            GH_FLAGS+=(--prerelease)
        fi

        gh release create "$TAG" \
            "${WHEEL_FILE}" \
            "${SDIST}" \
            "${GH_FLAGS[@]}"

        echo "  GitHub release: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"
    fi
fi

# ── 9. PyPI upload ────────────────────────────────────────────────────────────
if [[ "$UPLOAD" == true ]]; then
    echo ""
    if [[ "$TEST_PYPI" == true ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Uploading to TestPyPI"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$PYTHON" -m twine upload --repository testpypi "$REPO_ROOT/dist/python/"*
        echo ""
        echo "  Test install with:"
        echo "    pip install -i https://test.pypi.org/simple/ airgap-devkit==$VERSION"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Uploading to PyPI"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$PYTHON" -m twine upload "$REPO_ROOT/dist/python/"*
        echo ""
        echo "  Install with:"
        echo "    pip install airgap-devkit==$VERSION"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done — v$VERSION"
if [[ "$UPLOAD" == false ]]; then
    echo ""
    echo "  To publish (PyPI + GitHub release):"
    echo "    bash scripts/internal/release.sh $VERSION --no-build --skip-sign --skip-vt --upload"
    echo ""
    echo "  Signing env vars:  CODESIGN_CERT, CODESIGN_PASSWD, GPG_KEY_ID"
    echo "  VT scan env var:   VT_API_KEY  (skip with --skip-vt)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
