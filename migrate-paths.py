#!/usr/bin/env python3
"""
migrate-paths.py — updates internal path references in all scripts
after the Option D restructure.

Run from repo root AFTER migrate.py has been run.

Usage:
    python3 migrate-paths.py [--dry-run]
"""
import subprocess
import sys
import re
from pathlib import Path

DRY_RUN = "--dry-run" in sys.argv

# -----------------------------------------------------------------------
# Path mapping: old path fragment -> new path fragment
# Order matters — more specific patterns first
# -----------------------------------------------------------------------
PATH_REPLACEMENTS = [
    # Module root moves
    ("toolchains/clang/source-build",   "toolchains/clang/source-build"),
    ("toolchains/clang/style-formatter","toolchains/clang/style-formatter"),
    ("toolchains/clang",                "toolchains/clang"),
    ("toolchains/gcc/linux/cross",                 "toolchains/gcc/linux/cross"),
    ("toolchains/gcc/linux/native",               "toolchains/gcc/linux/native"),
    ("toolchains/clang",            "toolchains/clang"),
    ("toolchains/gcc/windows", "toolchains/gcc/windows"),
    ("dev-tools/7zip",             "dev-tools/7zip"),
    ("dev-tools/servy",            "dev-tools/servy"),
    ("frameworks/grpc",         "frameworks/grpc"),
    ("build-tools/lcov",         "build-tools/lcov"),
    ("dev-tools/vscode-extensions",         "dev-tools/dev-tools/vscode-extensions"),
    ("dev-tools/git-bundle",                "dev-tools/dev-tools/git-bundle"),

    # bootstrap.sh -> setup.sh renames (in path references)
    ("toolchains/gcc/linux/cross/setup.sh",    "toolchains/gcc/linux/cross/setup.sh"),
    ("toolchains/gcc/windows/setup.sh",         "toolchains/gcc/windows/setup.sh"),
    ("toolchains/clang/source-build/setup.sh",  "toolchains/clang/source-build/setup.sh"),
    ("build-tools/cmake/setup.sh",              "build-tools/cmake/setup.sh"),
    ("build-tools/lcov/setup.sh",               "build-tools/lcov/setup.sh"),
    ("languages/python/setup.sh",               "languages/python/setup.sh"),
    ("dev-tools/dev-tools/vscode-extensions/setup.sh",    "dev-tools/dev-tools/vscode-extensions/setup.sh"),

    # prebuilt-binaries submodule internal paths
    ("prebuilt-binaries/toolchains/clang",          "prebuilt-binaries/toolchains/clang/source-build"),
    ("prebuilt-binaries/toolchains/clang/clang-rhel8",  "prebuilt-binaries/toolchains/clang/rhel8"),
    ("prebuilt-binaries/toolchains/clang/clang-linux",  "prebuilt-binaries/toolchains/clang/source-build"),
    ("prebuilt-binaries/toolchains/clang/llvm-mingw",   "prebuilt-binaries/toolchains/clang/mingw"),
    ("prebuilt-binaries/toolchains/clang",       "prebuilt-binaries/toolchains/clang"),
    ("prebuilt-binaries/toolchains/gcc/linux/native",          "prebuilt-binaries/toolchains/gcc/linux"),
    ("prebuilt-binaries/toolchains/gcc/windows",     "prebuilt-binaries/toolchains/gcc/windows"),
    ("prebuilt-binaries/dev-tools/7zip",                 "prebuilt-binaries/dev-tools/7zip"),
    ("prebuilt-binaries/dev-tools/servy",                "prebuilt-binaries/dev-tools/servy"),
    ("prebuilt-binaries/build-tools/cmake",                "prebuilt-binaries/build-tools/cmake"),

    # Install paths (these appear in scripts as string literals)
    ("/opt/airgap-cpp-devkit/toolchains/gcc/linux/native",    "/opt/airgap-cpp-devkit/toolchains/gcc/linux/native"),
    ("/opt/airgap-cpp-devkit/toolchains/clang", "/opt/airgap-cpp-devkit/toolchains/clang"),
    ("/opt/airgap-cpp-devkit/toolchains/gcc/linux/cross",      "/opt/airgap-cpp-devkit/toolchains/gcc/linux/cross"),

    # LOCALAPPDATA paths (Windows)
    ("airgap-cpp-devkit/toolchains/gcc/linux/native",    "airgap-cpp-devkit/toolchains/gcc/linux/native"),
    ("airgap-cpp-devkit/toolchains/clang", "airgap-cpp-devkit/toolchains/clang"),
]

# Files to update — all .sh, .py, .json, .md in the repo
# Excludes .git/, prebuilt-binaries/ (submodule handles itself)
EXCLUDE_DIRS = {".git", "prebuilt-binaries"}

def find_files():
    extensions = {".sh", ".py", ".json", ".md", ".bat", ".txt"}
    for path in Path(".").rglob("*"):
        if any(part in EXCLUDE_DIRS for part in path.parts):
            continue
        if path.is_file() and path.suffix in extensions:
            yield path

def update_file(filepath):
    try:
        content = filepath.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False

    original = content
    for old, new in PATH_REPLACEMENTS:
        content = content.replace(old, new)

    if content != original:
        if DRY_RUN:
            print(f"  [DRY] Would update: {filepath}")
            # Show what changed
            old_lines = original.splitlines()
            new_lines = content.splitlines()
            for i, (o, n) in enumerate(zip(old_lines, new_lines)):
                if o != n:
                    print(f"    line {i+1}: {o.strip()[:80]}")
                    print(f"         -> {n.strip()[:80]}")
        else:
            filepath.write_text(content, encoding="utf-8")
            print(f"  [UPD] {filepath}")
        return True
    return False

print("=== Path Reference Updater ===")
print(f"Mode: {'DRY RUN' if DRY_RUN else 'LIVE'}")
print()

updated = []
skipped = []

for filepath in sorted(find_files()):
    if update_file(filepath):
        updated.append(filepath)
    else:
        skipped.append(filepath)

print()
print(f"Updated: {len(updated)} files")
print(f"Unchanged: {len(skipped)} files")
print()
if not DRY_RUN and updated:
    print("Run: git add -u  to stage all modified files")