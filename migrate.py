#!/usr/bin/env python3
"""
migrate.py — airgap-cpp-devkit Option D restructure migration.

Runs all git mv operations to move from the current flat structure
to the Option D category-based structure. Run from repo root.

Usage:
    python3 migrate.py [--dry-run]
"""
import subprocess
import sys
import os
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
    """git mv src dst, creating parent dirs as needed."""
    if not DRY_RUN:
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
    run(["git", "mv", src, dst])

def mkdir(path):
    if not DRY_RUN:
        Path(path).mkdir(parents=True, exist_ok=True)
    # add .gitkeep so git tracks empty dirs
    gitkeep = f"{path}/.gitkeep"
    if not DRY_RUN and not Path(gitkeep).exists():
        Path(gitkeep).touch()
        run(["git", "add", gitkeep])

print("=== airgap-cpp-devkit Option D Restructure ===")
print(f"Mode: {'DRY RUN' if DRY_RUN else 'LIVE'}")
print()

# Verify we're in the repo root
if not Path("install.sh").exists():
    print("ERROR: Run from repo root (install.sh not found)")
    sys.exit(1)

# -----------------------------------------------------------------------
# 1. toolchains/gcc/windows/  ← toolchains/gcc/windows/
# -----------------------------------------------------------------------
print("--- toolchains/gcc/windows (winlibs) ---")
git_mv("toolchains/gcc/windows/setup.sh",      "toolchains/gcc/windows/setup.sh")
git_mv("toolchains/gcc/windows/manifest.json",  "toolchains/gcc/windows/manifest.json")
git_mv("toolchains/gcc/windows/sbom.spdx.json", "toolchains/gcc/windows/sbom.spdx.json")
git_mv("toolchains/gcc/windows/README.md",       "toolchains/gcc/windows/README.md")
git_mv("toolchains/gcc/windows/.gitignore",      "toolchains/gcc/windows/.gitignore")
git_mv("toolchains/gcc/windows/scripts",         "toolchains/gcc/windows/scripts")
git_mv("toolchains/gcc/windows/docs",            "toolchains/gcc/windows/docs")
git_mv("toolchains/gcc/windows/vendor",          "toolchains/gcc/windows/vendor")

# -----------------------------------------------------------------------
# 2. toolchains/gcc/linux/cross/  ← toolchains/gcc/linux/cross/
# -----------------------------------------------------------------------
print("--- toolchains/gcc/linux/cross (tttapa cross-compiler) ---")
git_mv("toolchains/gcc/linux/cross/setup.sh",   "toolchains/gcc/linux/cross/setup.sh")
git_mv("toolchains/gcc/linux/cross/manifest.json",  "toolchains/gcc/linux/cross/manifest.json")
git_mv("toolchains/gcc/linux/cross/sbom.spdx.json", "toolchains/gcc/linux/cross/sbom.spdx.json")
git_mv("toolchains/gcc/linux/cross/README.md",      "toolchains/gcc/linux/cross/README.md")
git_mv("toolchains/gcc/linux/cross/scripts",        "toolchains/gcc/linux/cross/scripts")
git_mv("toolchains/gcc/linux/cross/vendor",         "toolchains/gcc/linux/cross/vendor")

# -----------------------------------------------------------------------
# 3. toolchains/gcc/linux/native/  ← toolchains/gcc/linux/native/
# -----------------------------------------------------------------------
print("--- toolchains/gcc/linux/native (toolchains/gcc/linux/native-15) ---")
git_mv("toolchains/gcc/linux/native/setup.sh",      "toolchains/gcc/linux/native/setup.sh")
git_mv("toolchains/gcc/linux/native/manifest.json", "toolchains/gcc/linux/native/manifest.json")
git_mv("toolchains/gcc/linux/native/README.md",     "toolchains/gcc/linux/native/README.md")
git_mv("toolchains/gcc/linux/native/scripts",       "toolchains/gcc/linux/native/scripts")
if Path("toolchains/gcc/linux/native/.gitignore").exists():
    git_mv("toolchains/gcc/linux/native/.gitignore", "toolchains/gcc/linux/native/.gitignore")

# -----------------------------------------------------------------------
# 4. toolchains/clang/source-build/  ← toolchains/clang/source-build/
# -----------------------------------------------------------------------
print("--- toolchains/clang/source-build ---")
git_mv("toolchains/clang/source-build/setup.sh",   "toolchains/clang/source-build/setup.sh")
git_mv("toolchains/clang/source-build/manifest.json",  "toolchains/clang/source-build/manifest.json")
git_mv("toolchains/clang/source-build/sbom.spdx.json", "toolchains/clang/source-build/sbom.spdx.json")
git_mv("toolchains/clang/source-build/README.md",      "toolchains/clang/source-build/README.md")
git_mv("toolchains/clang/source-build/.gitignore",     "toolchains/clang/source-build/.gitignore")
git_mv("toolchains/clang/source-build/bin",            "toolchains/clang/source-build/bin")
git_mv("toolchains/clang/source-build/scripts",        "toolchains/clang/source-build/scripts")
git_mv("toolchains/clang/source-build/llvm-src",       "toolchains/clang/source-build/llvm-src")
git_mv("toolchains/clang/source-build/ninja-src",      "toolchains/clang/source-build/ninja-src")
git_mv("toolchains/clang/source-build/demo",           "toolchains/clang/source-build/demo")
git_mv("toolchains/clang/source-build/docs",           "toolchains/clang/source-build/docs")

# -----------------------------------------------------------------------
# 5. toolchains/clang/style-formatter/  ← toolchains/clang/style-formatter/
# -----------------------------------------------------------------------
print("--- toolchains/clang/style-formatter ---")
git_mv("toolchains/clang/style-formatter", "toolchains/clang/style-formatter")

# -----------------------------------------------------------------------
# 6. toolchains/clang/rhel8/  ← toolchains/clang/ (clang-rhel8 component)
# -----------------------------------------------------------------------
print("--- toolchains/clang/rhel8 ---")
# The toolchains/clang module handled both rhel8 and mingw — split it
# Create rhel8 module from toolchains/clang pieces
mkdir("toolchains/clang/rhel8/scripts")

# -----------------------------------------------------------------------
# 7. toolchains/clang/mingw/  ← toolchains/clang/ (mingw component)
# -----------------------------------------------------------------------
print("--- toolchains/clang/mingw ---")
mkdir("toolchains/clang/mingw/scripts")

# toolchains/clang root files split between rhel8 and mingw — handled by new scripts
# The manifest/setup/verify scripts will be replaced with new per-component versions

# -----------------------------------------------------------------------
# 8. build-tools/cmake/  ← cmake/
# -----------------------------------------------------------------------
print("--- build-tools/cmake ---")
git_mv("cmake/bootstrap.sh",   "build-tools/cmake/setup.sh")
git_mv("cmake/manifest.json",  "build-tools/cmake/manifest.json")
git_mv("cmake/README.md",      "build-tools/cmake/README.md")

# -----------------------------------------------------------------------
# 9. build-tools/lcov/  ← build-tools/lcov/
# -----------------------------------------------------------------------
print("--- build-tools/lcov ---")
git_mv("build-tools/lcov/setup.sh",   "build-tools/lcov/setup.sh")
git_mv("build-tools/lcov/manifest.json",  "build-tools/lcov/manifest.json")
git_mv("build-tools/lcov/sbom.spdx.json", "build-tools/lcov/sbom.spdx.json")
git_mv("build-tools/lcov/README.md",      "build-tools/lcov/README.md")
git_mv("build-tools/lcov/.gitignore",     "build-tools/lcov/.gitignore")
git_mv("build-tools/lcov/scripts",        "build-tools/lcov/scripts")
git_mv("build-tools/lcov/vendor",         "build-tools/lcov/vendor")
git_mv("build-tools/lcov/demo",           "build-tools/lcov/demo")

# -----------------------------------------------------------------------
# 10. languages/python/  ← python/
# -----------------------------------------------------------------------
print("--- languages/python ---")
git_mv("python/bootstrap.sh",   "languages/python/setup.sh")
git_mv("python/manifest.json",  "languages/python/manifest.json")
git_mv("python/sbom.spdx.json", "languages/python/sbom.spdx.json")
git_mv("python/README.md",      "languages/python/README.md")
git_mv("python/scripts",        "languages/python/scripts")
git_mv("python/vendor",         "languages/python/vendor")

# -----------------------------------------------------------------------
# 11. dev-tools/dev-tools/vscode-extensions/  ← dev-tools/vscode-extensions/
# -----------------------------------------------------------------------
print("--- dev-tools/dev-tools/vscode-extensions ---")
git_mv("dev-tools/vscode-extensions/setup.sh",   "dev-tools/dev-tools/vscode-extensions/setup.sh")
git_mv("dev-tools/vscode-extensions/manifest.json",  "dev-tools/dev-tools/vscode-extensions/manifest.json")
git_mv("dev-tools/vscode-extensions/sbom.spdx.json", "dev-tools/dev-tools/vscode-extensions/sbom.spdx.json")
git_mv("dev-tools/vscode-extensions/README.md",      "dev-tools/dev-tools/vscode-extensions/README.md")
git_mv("dev-tools/vscode-extensions/vendor",         "dev-tools/dev-tools/vscode-extensions/vendor")

# -----------------------------------------------------------------------
# 12. dev-tools/dev-tools/git-bundle/  ← dev-tools/git-bundle/
# -----------------------------------------------------------------------
print("--- dev-tools/dev-tools/git-bundle ---")
git_mv("dev-tools/git-bundle/bundle.py",        "dev-tools/dev-tools/git-bundle/bundle.py")
git_mv("dev-tools/git-bundle/export.py",        "dev-tools/dev-tools/git-bundle/export.py")
git_mv("dev-tools/git-bundle/README.md",        "dev-tools/dev-tools/git-bundle/README.md")
git_mv("dev-tools/git-bundle/sbom.spdx.json",   "dev-tools/dev-tools/git-bundle/sbom.spdx.json")
git_mv("dev-tools/git-bundle/.gitignore",       "dev-tools/dev-tools/git-bundle/.gitignore")
git_mv("dev-tools/git-bundle/tests",            "dev-tools/dev-tools/git-bundle/tests")
git_mv("dev-tools/git-bundle/logs",             "dev-tools/dev-tools/git-bundle/logs")

# -----------------------------------------------------------------------
# 13. dev-tools/7zip/  ← dev-tools/7zip/
# -----------------------------------------------------------------------
print("--- dev-tools/7zip ---")
git_mv("dev-tools/7zip/setup.sh",      "dev-tools/7zip/setup.sh")
git_mv("dev-tools/7zip/manifest.json", "dev-tools/7zip/manifest.json")
git_mv("dev-tools/7zip/sbom.spdx.json","dev-tools/7zip/sbom.spdx.json")
git_mv("dev-tools/7zip/README.md",     "dev-tools/7zip/README.md")
git_mv("dev-tools/7zip/.gitignore",    "dev-tools/7zip/.gitignore")
git_mv("dev-tools/7zip/scripts",       "dev-tools/7zip/scripts")

# -----------------------------------------------------------------------
# 14. dev-tools/servy/  ← dev-tools/servy/
# -----------------------------------------------------------------------
print("--- dev-tools/servy ---")
git_mv("dev-tools/servy/setup.sh",      "dev-tools/servy/setup.sh")
git_mv("dev-tools/servy/manifest.json", "dev-tools/servy/manifest.json")
git_mv("dev-tools/servy/sbom.spdx.json","dev-tools/servy/sbom.spdx.json")
git_mv("dev-tools/servy/README.md",     "dev-tools/servy/README.md")
git_mv("dev-tools/servy/.gitignore",    "dev-tools/servy/.gitignore")
git_mv("dev-tools/servy/scripts",       "dev-tools/servy/scripts")

# -----------------------------------------------------------------------
# 15. frameworks/grpc/  ← frameworks/grpc/
# -----------------------------------------------------------------------
print("--- frameworks/grpc ---")
git_mv("frameworks/grpc/setup_grpc.sh",  "frameworks/grpc/setup.sh")
git_mv("frameworks/grpc/setup_grpc.bat", "frameworks/grpc/setup.bat")
git_mv("frameworks/grpc/manifest.json",  "frameworks/grpc/manifest.json")
git_mv("frameworks/grpc/README.md",      "frameworks/grpc/README.md")
git_mv("frameworks/grpc/.gitignore",     "frameworks/grpc/.gitignore")
git_mv("frameworks/grpc/scripts",        "frameworks/grpc/scripts")
git_mv("frameworks/grpc/vendor",         "frameworks/grpc/vendor")

# -----------------------------------------------------------------------
# prebuilt-binaries/ submodule moves
# -----------------------------------------------------------------------
print()
print("--- prebuilt-binaries submodule ---")
print("NOTE: Run migrate-prebuilt.py separately inside prebuilt-binaries/")

print()
print("=== Main repo moves complete ===")
print()
print("Next steps:")
print("  1. Run: python3 migrate-prebuilt.py  (inside prebuilt-binaries/)")
print("  2. Update path references in all scripts (migrate-paths.py)")
print("  3. git add -A && git status")
print("  4. Review, then git commit")