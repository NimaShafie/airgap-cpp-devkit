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

def find_compile_db(root):
    for candidate in [os.path.join(root, 'build', 'compile_commands.json'), os.path.join(root, 'out', 'compile_commands.json'), os.path.join(root, 'compile_commands.json')]:
        if os.path.isfile(candidate):
            return os.path.dirname(candidate)
    return None

def main():
    if '--help' in sys.argv:
        print('Runs clang-tidy on staged C and C++ files when clang-tidy and compile_commands.json are available.')
        return 0
    root = repo_root()
    os.chdir(root)
    files = staged_files()
    if not files:
        return 0
    try:
        run(['clang-tidy', '--version'], capture_output=True)
    except Exception:
        print('WARNING: clang-tidy not found. Skipping clang-tidy.')
        return 0
    build_dir = find_compile_db(root)
    if not build_dir:
        print('WARNING: compile_commands.json not found. Skipping clang-tidy.')
        return 0
    config_file = os.path.join(root, 'tools', 'coding-standard', '.clang-tidy')
    if not os.path.isfile(config_file):
        print('ERROR: clang-tidy config file not found: ' + config_file)
        return 1
    failed = False
    for path in files:
        if not os.path.isfile(path):
            continue
        result = subprocess.run(['clang-tidy', path, '-p=' + build_dir, '--config-file=' + config_file], text=True)
        if result.returncode != 0:
            failed = True
    if failed:
        print('clang-tidy reported issues. Commit aborted.')
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
