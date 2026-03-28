#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# create-test-repo.sh — Spin up a temporary local git repository and
#                        run the pre-commit hook end-to-end.
#
# Creates a fully isolated test environment:
#   • A bare "remote" (simulates Bitbucket, no network needed)
#   • A working clone of that remote
#   • The toolchains/clang-style-formatter submodule wired in
#   • The pre-commit hook installed
#   • A set of test C++ files: some PASSING, some FAILING
#
# Runs the hook, reports results, and cleans up unless --keep is passed.
#
# Usage:
#   bash scripts/create-test-repo.sh [--keep] [--dir /path/to/workdir]
#
# Options:
#   --keep        Do not delete the test directory on exit.
#   --dir <path>  Where to create the test environment (default: /tmp or %TEMP%).
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
KEEP=false
BASE_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep)       KEEP=true;         shift ;;
        --dir)        BASE_DIR="$2";     shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--keep] [--dir <path>]"
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Locate the submodule root (this script lives in scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Work directory
if [[ -z "${BASE_DIR}" ]]; then
    BASE_DIR="${TMPDIR:-/tmp}"
    # On Windows Git Bash TMPDIR might be unset
    [[ -z "${BASE_DIR}" || ! -d "${BASE_DIR}" ]] && BASE_DIR="$(pwd)/tmp-test"
fi

WORK_DIR="${BASE_DIR}/llvm-hook-test-$$"
mkdir -p "${WORK_DIR}"

echo "=================================================================="
echo "  toolchains/clang-style-formatter — end-to-end hook test"
echo "  Work dir: ${WORK_DIR}"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------
cleanup() {
    if [[ "${KEEP}" == "false" ]]; then
        echo ""
        echo "[test] Cleaning up ${WORK_DIR}…"
        rm -rf "${WORK_DIR}"
    else
        echo ""
        echo "[test] Test directory retained at: ${WORK_DIR}"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1.  Create a bare "remote" repository
# ---------------------------------------------------------------------------
BARE_REMOTE="${WORK_DIR}/remote.git"
echo "[test] Creating bare remote at: ${BARE_REMOTE}"
git init --bare "${BARE_REMOTE}" -q
git -C "${BARE_REMOTE}" config core.bare true

# ---------------------------------------------------------------------------
# 2.  Clone the remote into a working directory
# ---------------------------------------------------------------------------
HOST_REPO="${WORK_DIR}/host-repo"
echo "[test] Cloning into: ${HOST_REPO}"
git clone "${BARE_REMOTE}" "${HOST_REPO}" -q

# Minimal identity so git commit works without global config
git -C "${HOST_REPO}" config user.email "test@llvm-hook-test.local"
git -C "${HOST_REPO}" config user.name  "Hook Test Runner"

# ---------------------------------------------------------------------------
# 3.  Wire in the toolchains/clang-style-formatter submodule
# ---------------------------------------------------------------------------
echo "[test] Adding toolchains/clang-style-formatter as submodule (toolchains/clang-style-formatter/)…"

# Use the local submodule root as the "remote URL" — perfect for air-gapped.
git -C "${HOST_REPO}" submodule add \
    --name toolchains/clang-style-formatter \
    "${SUBMODULE_ROOT}" \
    toolchains/clang-style-formatter 2>/dev/null

git -C "${HOST_REPO}" submodule update --init --recursive -q

# ---------------------------------------------------------------------------
# 4.  Install the hook
# ---------------------------------------------------------------------------
echo "[test] Installing pre-commit hook…"
bash "${HOST_REPO}/toolchains/clang-style-formatter/scripts/install-hooks.sh" \
    --force 2>&1 | sed 's/^/             /'

# ---------------------------------------------------------------------------
# 5.  Create test C++ source files
# ---------------------------------------------------------------------------
echo "[test] Creating test C++ source files…"

CPP_SRC_DIR="${HOST_REPO}/src"
mkdir -p "${CPP_SRC_DIR}"

# ---- PASSING file: already LLVM-formatted ----
cat > "${CPP_SRC_DIR}/good.cpp" << 'GOOD'
//===--- good.cpp - Correct LLVM-style file ---------------===//
//
// This file is correctly formatted per the LLVM coding standard.
//
//===--------------------------------------------------------------===//

#include <cstdio>
#include <string>

namespace example {

/// A simple greeter function.
void greet(const std::string &name) {
  if (name.empty()) {
    printf("Hello, world!\n");
    return;
  }
  printf("Hello, %s!\n", name.c_str());
}

class Widget {
public:
  explicit Widget(int value) : value_(value) {}

  int getValue() const { return value_; }

  void setValue(int v) { value_ = v; }

private:
  int value_;
};

} // namespace example
GOOD

# ---- FAILING file: bad indentation, wrong brace style, trailing spaces ----
cat > "${CPP_SRC_DIR}/bad_indent.cpp" << 'BAD_INDENT'
#include <cstdio>
#include <string>

namespace example
{   // brace on wrong line
    void badFunction(const std::string& name)  // & on wrong side
    {                                          // brace on wrong line
        if(name.empty())                       // no space before paren
        {                                      // brace on wrong line
            printf("Hello!\n");    
        }                    
        else
        {
            printf("Hello, %s!\n", name.c_str());         
        }
    }
    
    class BadWidget
    {
        public :           // wrong indentation, space before colon
            BadWidget(int value)
            {
                val = value;
            }
            int getVal() { return val; }
        private :
            int val;
    };
}
BAD_INDENT

# ---- FAILING file: magic numbers, no-space operators ----
cat > "${CPP_SRC_DIR}/bad_style.cpp" << 'BAD_STYLE'
#include<cstdio>

int compute(int x,int y,int z){
    int result=x*2+y*3-z/4;
    if(result>100){
    printf("big\n");}
    else{
    printf("small\n");}
    return result;}
BAD_STYLE

# ---- PASSING file: simple header ----
cat > "${CPP_SRC_DIR}/good.h" << 'GOOD_H'
//===--- good.h - Example header --------------------------===//
#ifndef EXAMPLE_GOOD_H
#define EXAMPLE_GOOD_H

#include <string>

namespace example {

void greet(const std::string &name);

class Widget {
public:
  explicit Widget(int value);
  int getValue() const;
  void setValue(int v);

private:
  int value_;
};

} // namespace example

#endif // EXAMPLE_GOOD_H
GOOD_H

# Also create a .gitignore and a README so the first commit has something
cat > "${HOST_REPO}/.gitignore" << 'GITIGNORE'
build/
*.o
*.obj
compile_commands.json
toolchains/clang-style-formatter-local/
GITIGNORE

cat > "${HOST_REPO}/README.md" << 'README'
# Hook Test Repository

This is a temporary test repository created by `create-test-repo.sh`.
README

# ---------------------------------------------------------------------------
# 6.  Test A — commit only CLEAN files (should PASS)
# ---------------------------------------------------------------------------
echo ""
echo "──────────────────────────────────────────────────────────────────"
echo "  TEST A: Committing only well-formatted files (expect: PASS)"
echo "──────────────────────────────────────────────────────────────────"

git -C "${HOST_REPO}" add .gitignore README.md toolchains/clang-style-formatter \
    "${CPP_SRC_DIR}/good.cpp" "${CPP_SRC_DIR}/good.h"

PASS_A=false
if git -C "${HOST_REPO}" commit -m "chore: initial commit with clean files" -q 2>&1; then
    echo "  ✓ PASS — Clean commit accepted as expected."
    PASS_A=true
else
    echo "  ✗ FAIL — Clean commit was incorrectly rejected!"
fi

# ---------------------------------------------------------------------------
# 7.  Test B — stage BAD files and try to commit (should FAIL)
# ---------------------------------------------------------------------------
echo ""
echo "──────────────────────────────────────────────────────────────────"
echo "  TEST B: Committing badly-formatted files (expect: FAIL/REJECT)"
echo "──────────────────────────────────────────────────────────────────"

git -C "${HOST_REPO}" add \
    "${CPP_SRC_DIR}/bad_indent.cpp" \
    "${CPP_SRC_DIR}/bad_style.cpp"

PASS_B=false
if git -C "${HOST_REPO}" commit -m "feat: add badly formatted files" 2>&1 | \
        grep -q "commit REJECTED"; then
    echo "  ✓ PASS — Badly-formatted commit was correctly rejected."
    PASS_B=true
else
    echo "  ✗ FAIL — Badly-formatted commit was NOT rejected (hook may not be running)!"
fi

# ---------------------------------------------------------------------------
# 8.  Test C — auto-fix the bad files, then commit (should PASS)
# ---------------------------------------------------------------------------
echo ""
echo "──────────────────────────────────────────────────────────────────"
echo "  TEST C: Auto-fix bad files then commit (expect: PASS)"
echo "──────────────────────────────────────────────────────────────────"

# The bad files are already staged; run fix-format.sh from within the repo
pushd "${HOST_REPO}" > /dev/null
bash "toolchains/clang-style-formatter/scripts/fix-format.sh" 2>&1 | sed 's/^/  /'
popd > /dev/null

PASS_C=false
if git -C "${HOST_REPO}" commit -m "fix: auto-format bad files" -q 2>&1; then
    echo "  ✓ PASS — Fixed commit accepted."
    PASS_C=true
else
    echo "  ✗ FAIL — Fixed commit was still rejected (clang-format may be unavailable)!"
fi

# ---------------------------------------------------------------------------
# 9.  Summary
# ---------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo "  Test Summary"
echo "=================================================================="
_status() { [[ "$1" == "true" ]] && echo "✓ PASS" || echo "✗ FAIL"; }
echo "  A (clean commit accepted)  : $(_status "${PASS_A}")"
echo "  B (bad commit rejected)    : $(_status "${PASS_B}")"
echo "  C (fixed commit accepted)  : $(_status "${PASS_C}")"
echo ""

ALL_PASSED=true
[[ "${PASS_A}" == "true" && "${PASS_B}" == "true" && "${PASS_C}" == "true" ]] || ALL_PASSED=false

if [[ "${ALL_PASSED}" == "true" ]]; then
    echo "  All tests passed ✓  The hook is working correctly."
    echo ""
    exit 0
else
    echo "  One or more tests failed — see output above for details."
    echo "  Run with --keep to inspect the test repository."
    echo ""
    exit 1
fi