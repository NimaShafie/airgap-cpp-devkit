# test-repo

Disposable validation repo for the coding standard kit.

## Purpose

- Verify repo-local hooks without touching global Git config
- Verify clang-format reformats staged files
- Verify the first commit fails when formatting changes are made
- Verify the second commit succeeds

## Temporary Git state options

### Option 1: repo-local config only

```bat
git config --local core.hooksPath tools/coding-standard/hooks
```

### Option 2: one-shot commit with no saved config

```bat
git -c core.hooksPath=tools/coding-standard/hooks commit -m "Test hook"
```

## Windows test flow

```bat
git init
git add .
git commit -m "Initial import"
setup-coding-standard.cmd
git add src/bad_format.cpp
git commit -m "Test formatting hook"
```

Expected behavior:

- first formatting commit aborts after reformatting the file
- second commit succeeds
