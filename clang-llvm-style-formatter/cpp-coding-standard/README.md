# cpp-coding-standard

Windows-first, offline-friendly C++ formatting and linting kit for multiple repositories.

## Design goals

- No administrator privileges required
- No system PATH changes
- No global Git configuration changes
- Repo-local Git hook installation only
- User-scope LLVM tool install only when needed
- `.clang-format` at product repo root for native editor integration
- `.clang-tidy` and hook logic centralized under `tools/coding-standard/`

## What this kit does

The setup script:

1. Sets `core.hooksPath` for the current repository only
2. Verifies `.clang-format` exists at the repo root
3. Verifies `tools/coding-standard/.clang-tidy` exists
4. Verifies Python is installed
5. Verifies `clang-format` is available
6. If `clang-format` is missing, attempts a non-admin user-scope install from bundled portable binaries
7. Verifies `clang-tidy` if available, and attempts the same non-admin user-scope install if bundled
8. Warns only if `clang-tidy` is still unavailable
9. Optionally performs a smoke test

## Non-admin behavior

This project does not modify:

- System PATH
- Machine-wide environment variables
- Global Git configuration
- HKLM registry keys

This project may modify:

- The current repository `.git/config`
- The current user's PATH only, if tool install is needed and bundled binaries are present
- The current user's local app data folder for user-scope LLVM tools

## Repository layout

```text
cpp-coding-standard/
  .clang-format
  .gitignore
  README.md
  hooks/
  scripts/
  docs/
  metadata/
  templates/
  vendor/
```

## How product repos consume this

In each product repo:

```text
product-repo/
  .clang-format
  tools/
    coding-standard/   <-- copy or submodule of this repo
```

The root `.clang-format` is the file editors discover automatically.
The central copy under `tools/coding-standard/` remains the source of truth and can be synced to the root file.

## Install in a product repo

From the product repo root on Windows:

```bat
setup-coding-standard.cmd
```

From the product repo root on Linux:

```bash
bash setup-coding-standard.sh
```

## Verify after install

```bat
git config --local --get core.hooksPath
clang-format --version
clang-tidy --version
py -3 --version
```

Expected local hooks path:

```text
tools/coding-standard/hooks
```

## Running the hook

```bat
git add src\example.cpp
git commit -m "Test formatting hook"
```

On the first commit, if formatting changes are needed, the hook reformats the file, re-stages it, and aborts the commit so the user can review the changes.

## Bundled portable tools

If `clang-format` is missing, the setup script looks for portable user-installable tools here:

```text
tools/coding-standard/vendor/windows/llvm/bin/
tools/coding-standard/vendor/linux/llvm/bin/
```

On Windows, if present, they are copied to:

```text
%LOCALAPPDATA%\cpp-coding-standard\llvmin
```

The script then adds that directory to the current user's PATH only.

## Test repo

A disposable local validation repo is included under `test-repo/` in the zip package.
It is intended for local testing without changing global Git configuration.

## Notes

- `clang-format` is required
- Python is required
- `clang-tidy` is optional but recommended
- `compile_commands.json` is optional and included only as an example template
- CI should still enforce formatting and linting, because local hooks can be bypassed with `--no-verify`
