#!/usr/bin/env python3
import os
import subprocess
import sys

CPP_EXTENSIONS = {'.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.hxx', '.ipp', '.inl'}

def run(cmd, check=True, capture_output=False):
    return subprocess.run(cmd, check=check, capture_output=capture_output, text=True)

def repo_root():
    return run(['git', 'rev-parse', '--show-toplevel'], capture_output=True).stdout.strip()

def staged_files():
    result = run(['git', 'diff', '--cached', '--name-only', '--diff-filter=ACMR'], capture_output=True)
    paths = []
    for line in result.stdout.splitlines():
        path = line.strip()
        if os.path.splitext(path)[1].lower() in CPP_EXTENSIONS:
            paths.append(path)
    return paths

def main():
    if '--help' in sys.argv:
        print('Formats staged C and C++ files with clang-format.')
        return 0
    root = repo_root()
    os.chdir(root)
    files = staged_files()
    if not files:
        return 0
    try:
        run(['clang-format', '--version'], capture_output=True)
    except Exception:
        print('ERROR: clang-format not found on PATH.')
        return 1
    changed = []
    for path in files:
        if not os.path.isfile(path):
            continue
        before = run(['git', 'hash-object', path], capture_output=True).stdout.strip()
        run(['clang-format', '-i', '-style=file', path])
        run(['git', 'add', path])
        after = run(['git', 'hash-object', path], capture_output=True).stdout.strip()
        if before != after:
            changed.append(path)
    if changed:
        print('clang-format updated these files:')
        for path in changed:
            print('  ' + path)
        print('Review the formatting changes and run commit again.')
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
