#!/usr/bin/env python3
"""
migrate-prebuilt.py — restructures prebuilt-binaries/ submodule.

Run from inside the prebuilt-binaries/ directory.

Usage:
    cd prebuilt-binaries
    python3 ../migrate-prebuilt.py [--dry-run]
"""
import subprocess
import sys
from pathlib import Path

DRY_RUN = "--dry-run" in sys.argv

def run(cmd, check=True):
    print(f"  {'[DRY]' if DRY_RUN else '[RUN]'} {' '.join(cmd)}")
    if not DRY_RUN:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if check and result.returncode != 0:
            print(f"  ERROR: {result.stderr.strip()}", file=sys.stderr)
            sys.exit(1)
        return result
    return None

def git_mv(src, dst):
    if not DRY_RUN:
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
    run(["git", "mv", src, dst])

print("=== prebuilt-binaries Option D Restructure ===")
print(f"Mode: {'DRY RUN' if DRY_RUN else 'LIVE'}")
print()

# Verify we're in prebuilt-binaries
if not Path(".git").exists() and not Path(".git").is_file():
    print("ERROR: Run from inside prebuilt-binaries/")
    sys.exit(1)

# -----------------------------------------------------------------------
# toolchains/gcc/windows/  ← winlibs-gcc-ucrt/
# -----------------------------------------------------------------------
print("--- toolchains/gcc/windows ---")
for f in Path("winlibs-gcc-ucrt").iterdir():
    if f.name != ".gitignore":
        git_mv(str(f), f"toolchains/gcc/windows/{f.name}")
if Path("winlibs-gcc-ucrt/.gitignore").exists():
    git_mv("winlibs-gcc-ucrt/.gitignore", "toolchains/gcc/windows/.gitignore")

# -----------------------------------------------------------------------
# toolchains/gcc/linux/  ← toolchains/gcc/linux/native/
# -----------------------------------------------------------------------
print("--- toolchains/gcc/linux ---")
for f in Path("toolchains/gcc/linux/native").iterdir():
    git_mv(str(f), f"toolchains/gcc/linux/{f.name}")

# -----------------------------------------------------------------------
# toolchains/clang/source-build/  ← toolchains/clang/
# -----------------------------------------------------------------------
print("--- toolchains/clang/source-build ---")
for f in Path("toolchains/clang").iterdir():
    git_mv(str(f), f"toolchains/clang/source-build/{f.name}")

# -----------------------------------------------------------------------
# toolchains/clang/rhel8/  ← toolchains/clang/clang-rhel8/
# -----------------------------------------------------------------------
print("--- toolchains/clang/rhel8 ---")
for f in Path("toolchains/clang/clang-rhel8").iterdir():
    git_mv(str(f), f"toolchains/clang/rhel8/{f.name}")

# -----------------------------------------------------------------------
# toolchains/clang/mingw/  ← toolchains/clang/llvm-mingw/
# -----------------------------------------------------------------------
print("--- toolchains/clang/mingw ---")
for f in Path("toolchains/clang/llvm-mingw").iterdir():
    git_mv(str(f), f"toolchains/clang/mingw/{f.name}")

# toolchains/clang/clang-linux/ also goes to source-build
print("--- toolchains/clang/source-build (clang-linux parts) ---")
for f in Path("toolchains/clang/clang-linux").iterdir():
    git_mv(str(f), f"toolchains/clang/source-build/{f.name}")

# -----------------------------------------------------------------------
# build-tools/cmake/  ← cmake/
# -----------------------------------------------------------------------
print("--- build-tools/cmake ---")
for f in Path("cmake").iterdir():
    git_mv(str(f), f"build-tools/cmake/{f.name}")

# -----------------------------------------------------------------------
# languages/python/  ← (python parts were committed to root of submodule)
# -----------------------------------------------------------------------
# Python parts are in python/ subdir of main repo vendor — check if any
# python parts exist directly in prebuilt-binaries root
print("--- languages/python (if present) ---")
python_parts = list(Path(".").glob("cpython-*.part-*"))
if python_parts:
    for f in python_parts:
        git_mv(str(f), f"languages/python/{f.name}")
else:
    print("  (no python parts at root — skipping)")

# -----------------------------------------------------------------------
# dev-tools/7zip/  ← 7zip/
# -----------------------------------------------------------------------
print("--- dev-tools/7zip ---")
for f in Path("7zip").iterdir():
    git_mv(str(f), f"dev-tools/7zip/{f.name}")

# -----------------------------------------------------------------------
# dev-tools/servy/  ← servy/
# -----------------------------------------------------------------------
print("--- dev-tools/servy ---")
for f in Path("servy").iterdir():
    git_mv(str(f), f"dev-tools/servy/{f.name}")

# -----------------------------------------------------------------------
# dev-tools/dev-tools/vscode-extensions/ — vsix parts live in main repo vendor,
# not in prebuilt-binaries. Nothing to move here.
# -----------------------------------------------------------------------

print()
print("=== prebuilt-binaries moves complete ===")
print()
print("Next steps:")
print("  git status   (verify all moves look correct)")
print("  git add -A && git commit -m 'refactor: restructure to Option D layout'")
print("  git push")