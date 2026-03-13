# Rollout Guide

## Recommended enterprise pattern

- Create one repo named `cpp-coding-standard`
- Store in it:
  - `.clang-format`
  - `.clang-tidy`
  - Git hooks
  - install scripts
  - helper scripts
  - optional bundled portable LLVM binaries or instructions
- Add that repo into each product repo under `tools/coding-standard/`
- In each product repo, keep a root `.clang-format`
- Point Git hooks to `tools/coding-standard/hooks` using `core.hooksPath`

## Option A vs Option B

### Option A: Full copy at root
The product repo root `.clang-format` is a normal copy of the authoritative formatting file.
This gives the best editor support and the least surprise for developers.

### Option B: Tiny root shim
A script refreshes the root `.clang-format` from the central repo copy.
Because clang-format does not support including another YAML config file directly, the "shim" is still effectively a copied root file.

## Concrete recommendation

Use Option A operationally, with a sync script to refresh the root file whenever the central standard changes.

## First-time setup in each product repo

1. Copy or add `cpp-coding-standard` under `tools/coding-standard/`
2. Run `tools\coding-standard\scripts\sync-root-clang-format.cmd`
3. Run `tools\coding-standard\scripts\install-user-tools.cmd`
4. Run `tools\coding-standard\scripts\install-hooks.cmd`
5. Run `tools\coding-standard\scripts\verify-toolchain.cmd`
6. Test a commit with a sample C++ file
