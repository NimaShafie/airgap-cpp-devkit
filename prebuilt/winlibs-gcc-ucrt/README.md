# prebuilt/winlibs-gcc-ucrt

Pre-built GCC toolchain package for air-gapped Windows environments.
Part of the `airgap-cpp-devkit` suite.

## Pinned Release

| Component   | Version                      |
|-------------|------------------------------|
| GCC         | 15.2.0 (POSIX threads)       |
| MinGW-w64   | 13.0.0 (UCRT)                |
| GDB         | 17.1                         |
| Binutils    | 2.46.0                       |
| CMake       | 4.2.3                        |
| Ninja       | 1.13.2                       |
| Release tag | `15.2.0posix-13.0.0-ucrt-r6` |
| Upstream    | [brechtsanders/winlibs_mingw] |

[brechtsanders/winlibs_mingw]: https://github.com/brechtsanders/winlibs_mingw/releases/tag/15.2.0posix-13.0.0-ucrt-r6

---

## Quickstart

```bash
cd prebuilt/winlibs-gcc-ucrt
bash setup.sh x86_64
```

That's it. `setup.sh` handles everything: part verification, reassembly,
archive integrity check, extraction, and smoke test. At the end it prints the
`source` command to activate the toolchain in your current shell.

Default architecture is `x86_64`. Pass `i686` for 32-bit.

---

## How It Works

The `.7z` (102MB) is too large to commit as a single file, so it is split into
three parts in `vendor/` and committed directly to git — no Git LFS required.

`setup.sh` runs the following in sequence:

```
verify.sh       — SHA256-checks each part against manifest.json
reassemble.sh   — cats parts into the .7z, SHA256-checks the result
install.sh      — extracts via 7z, smoke-tests gcc.exe
env-setup.sh    — source this to activate the toolchain (printed at end)
```

Every step is gated: if any hash check fails, setup stops immediately and
nothing is extracted.

---

## Integrity Model

`manifest.json` pins four SHA256 hashes:

| What                  | When checked         |
|-----------------------|----------------------|
| `part-aa` SHA256      | `verify.sh` (step 1) |
| `part-ab` SHA256      | `verify.sh` (step 1) |
| `part-ac` SHA256      | `verify.sh` (step 1) |
| Reassembled `.7z` SHA256 | `reassemble.sh` (step 2) |

The reassembled hash was cross-referenced from two independent sources before
being pinned:
1. Official GitHub release `.sha256` sidecar (`brechtsanders/winlibs_mingw`)
2. `ScoopInstaller/Main` package registry (`bucket/mingw-winlibs.json`)

---

## After Setup

Activate the toolchain in your current shell:

```bash
source scripts/env-setup.sh x86_64
gcc --version
```

Add to `~/.bashrc` for permanent activation:

```bash
echo "source '$(pwd)/scripts/env-setup.sh' x86_64" >> ~/.bashrc
```

---

## Layout

```
prebuilt/winlibs-gcc-ucrt/
├── setup.sh               ← single user entry point
├── manifest.json          ← version pin + all SHA256 hashes
├── scripts/
│   ├── verify.sh          ← checks parts or reassembled archive
│   ├── reassemble.sh      ← joins parts, verifies result
│   ├── install.sh         ← extracts + smoke tests
│   └── env-setup.sh       ← source to activate toolchain
├── vendor/
│   ├── *.part-aa          ← committed to git
│   ├── *.part-ab          ← committed to git
│   └── *.part-ac          ← committed to git
└── docs/
    └── offline-transfer.md
```

---

## Notes

- **No system install.** WinLibs is fully relocatable — extracts to
  `toolchain/x86_64/` with no registry writes or installers.
- **UCRT runtime.** Compiled binaries require UCRT, built into Windows 10+
  or installable on Windows 7 SP1+.
- **Coexists with LLVM.** This toolchain and `clang-llvm-source-build/` sit
  independently on PATH — `env-setup.sh` prepends for the current shell only.
- **`vendor/*.7z` is gitignored.** Only the three parts are committed.
  The reassembled archive is a local artifact produced by `reassemble.sh`.