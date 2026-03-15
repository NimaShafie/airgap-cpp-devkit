# llvm-src/ — Vendored LLVM/Clang Source

This directory contains a stripped subset of the LLVM/Clang source tree,
used to build `clang-format` on air-gapped developer machines.

## Contents

```
llvm-src/
├── llvm/                    ← LLVM core source
│   └── tools/clang/         ← Clang frontend (nested inside LLVM as required by cmake)
├── cmake/                   ← LLVM CMake build modules
├── third-party/             ← LLVM third-party build dependencies
├── SOURCE_INFO.txt          ← LLVM version, fetch date, original checksums
└── .gitignore               ← Excludes build/ and install/ directories
```

## What was stripped

To keep the repository size manageable (~250 MB instead of ~1 GB), the
following were removed from the upstream source before committing:

- All `test/` and `unittests/` directories
- All `benchmarks/` directories
- All `docs/` directories (build-time documentation source, not code comments)

These are not needed to compile `clang-format`.

## Updating the LLVM version

On a machine with internet access:

```bash
bash scripts/fetch-llvm-source.sh --version X.Y.Z
git add llvm-src/
git commit -m "vendor: update LLVM source to X.Y.Z"
```

See `scripts/fetch-llvm-source.sh --help` for options.

## Building

On any developer machine (air-gapped is fine — no network needed):

```bash
bash scripts/build-clang-format.sh
```

The compiled binary is placed at:
- `bin/windows/clang-format.exe` (Windows)
- `bin/linux/clang-format` (Linux)

The pre-commit hook discovers these paths automatically.
