# toolchains/clang-source-build

### Author: Nima Shafie

> **Optional** — builds `clang-format` and `clang-tidy` from LLVM source,
> or installs a pre-built `clang-tidy` binary (Linux only).
>
> Most developers should use the faster pip method for clang-format instead:
> ```bash
> bash toolchains/clang/style-formatter/bootstrap.sh   # ~5 seconds
> ```

---

## When to Use This

| Scenario | Recommended method |
|----------|-------------------|
| Windows — need clang-format + clang-tidy | `toolchains/clang/source-build/setup.sh` (this) — instant |
| Linux — Python 3.8+ available, clang-format only | `toolchains/clang/style-formatter/bootstrap.sh` (pip) |
| Linux — Python unavailable | `toolchains/clang/source-build/setup.sh` (this) |
| Policy requires source builds | `toolchains/clang/source-build/setup.sh --build-from-source` |
| Need clang-tidy on Linux | `toolchains/clang/source-build/setup.sh` (this) |

---

## Usage

```bash
bash toolchains/clang/source-build/setup.sh
```

**On Linux**, this does two things:

1. Builds `clang-format` from the vendored LLVM 22.1.1 source (~30-60 min)
2. Installs `clang-tidy` from the vendored pre-built binary — reassembles
   the split parts and verifies SHA256 against `manifest.json` (seconds)

**On Windows**, this does two things — both are instant (seconds, no compiler required):

1. Verifies the vendored pre-built `clang-format.exe` (3.1 MB, SHA256 check)
2. Verifies the vendored pre-built `clang-tidy.exe` (46 MB, SHA256 check)

To build both tools from LLVM source instead of using the vendored binaries:

```bash
bash toolchains/clang/source-build/setup.sh --build-from-source
```

**Build prerequisites are only required for `--build-from-source`:**

The binaries are placed at:

| Binary | Linux | Windows |
|--------|-------|---------|
| clang-format | `prebuilt-binaries/clang-format-linux` | `prebuilt-binaries/clang-format.exe` |
| clang-tidy | `prebuilt-binaries/clang-tidy-linux` | `prebuilt-binaries/clang-tidy.exe` |

`toolchains/clang/style-formatter/bootstrap.sh` detects these binaries automatically.
After this script completes, run the formatter bootstrap to install the hook:

```bash
bash toolchains/clang/style-formatter/bootstrap.sh
```

To force a full rebuild and re-verification:

```bash
bash toolchains/clang/source-build/setup.sh --rebuild
```

---

## Build Prerequisites

> **Windows developers using the default path do not need Visual Studio or CMake.**
> The vendored pre-built binaries are verified and ready after `git clone`.
> Prerequisites below only apply when using `--build-from-source`.

### Windows 11 (`--build-from-source` only)

| Tool | Minimum | Tested | Notes |
|------|---------|--------|-------|
| Visual Studio | 2017 any edition | VS Insiders 18 | "Desktop development with C++" workload required |
| MSVC toolchain | any | 14.50.35717 | Installed automatically with VS C++ workload |
| CMake | 3.14 | 4.1.2 | Bundled with VS 2019+; or install separately |
| Git Bash | any | MINGW64 | Run `bootstrap.sh` from Git Bash — not cmd.exe or PowerShell |

### RHEL 8

```bash
sudo dnf install gcc-c++ cmake python3
```

| Tool | Minimum | Tested |
|------|---------|--------|
| GCC | 8.0 | 8.5.0 (Red Hat 8.5.0-28) |
| CMake | 3.14 | system cmake on RHEL 8 |
| Python | 3.6 | pre-installed on RHEL 8 |

See [`docs/llvm-install-guide.md`](docs/llvm-install-guide.md) for detailed
instructions, troubleshooting, and known platform issues.

---

## How It Works

### clang-format on Windows (vendored pre-built binary)

1. Checks for an existing binary — skips if found (use `--rebuild` to override)
2. Runs `scripts/verify-clang-format-windows.sh`:
   - Verifies `prebuilt-binaries/clang-format.exe` SHA256 against `manifest.json`
   - Sets executable bit
3. Binary ready at `prebuilt-binaries/clang-format.exe`

### clang-format on Linux (source build)

1. Checks for an existing binary — skips rebuild if found (use `--rebuild` to override)
2. Runs `scripts/build-ninja.sh` — builds Ninja from `ninja-src/` (~30 sec)
3. Runs `scripts/extract-llvm-source.sh` — reassembles the split tarball and extracts (~5-15 min)
4. Runs `scripts/build-clang-format.sh` — compiles with CMake + Ninja (~30-60 min)
5. Binary placed in `prebuilt-binaries/clang-format-linux`

### clang-tidy on Linux (pre-built vendored binary)

1. Checks for an existing binary — skips if found (use `--rebuild` to override)
2. Runs `scripts/reassemble-clang-tidy.sh`:
   - Verifies each split part against SHA256 in `manifest.json`
   - Reassembles `prebuilt-binaries/clang-tidy.part-aa` + `prebuilt-binaries/clang-tidy.part-ab` → `clang-tidy-linux`
   - Verifies the assembled binary SHA256
   - Sets executable bit
3. Binary placed in `prebuilt-binaries/clang-tidy-linux`

### clang-tidy on Windows (vendored pre-built binary)

1. Checks for an existing binary — skips if found (use `--rebuild` to override)
2. Runs `scripts/verify-clang-tidy-windows.sh`:
   - Verifies `prebuilt-binaries/clang-tidy.exe` SHA256 against `manifest.json`
   - Sets executable bit
3. Binary ready at `prebuilt-binaries/clang-tidy.exe`

The Windows binary (46 MB) is committed directly to git — no splitting required.
Pass `--build-from-source` to compile from the vendored LLVM source instead.

---

## Using clang-tidy

After bootstrapping, the binary is at `prebuilt-binaries/clang-tidy-linux` (Linux)
or `prebuilt-binaries/clang-tidy.exe` (Windows).
A minimal usage example and a C++ file with intentional issues are in `demo/`:

```bash
bash toolchains/clang/source-build/demo/run-demo.sh
```

This runs `clang-tidy` against a sample file and shows the diagnostics output.
See [`demo/README.md`](demo/README.md) for details on each check category.

---

## Disk Space

| Phase | Space required |
|-------|---------------|
| LLVM source (extracted) | ~800 MB |
| Build directory (clang-format only) | ~2-3 GB |
| Build directory (clang-format + clang-tidy) | ~4-6 GB |
| Final binaries only | ~100-200 MB |

To reclaim build space after a successful build:

```bash
rm -rf toolchains/clang/source-build/llvm-src/build/
```

---

## Updating the Vendored LLVM Version (Maintainers Only)

On a machine with internet access:

```bash
bash toolchains/clang/source-build/scripts/fetch-llvm-source.sh --version 23.x.x
bash toolchains/clang/source-build/scripts/split-llvm-tarball.sh
git add toolchains/clang/source-build/llvm-src/
git commit -m "vendor: update LLVM to 23.x.x"
git push
```

Developers rebuild with:
```bash
bash toolchains/clang/source-build/setup.sh --rebuild
```

## Updating the Vendored clang-tidy Linux Binary (Maintainers Only)

Build `clang-tidy` from LLVM source on a RHEL 8 x86_64 machine, then split
and update the manifest:

```bash
strip prebuilt-binaries/clang-tidy-linux
split -b 52428800 prebuilt-binaries/clang-tidy-linux prebuilt-binaries/clang-tidy.part-
sha256sum prebuilt-binaries/clang-tidy-linux
sha256sum prebuilt-binaries/clang-tidy.part-aa prebuilt-binaries/clang-tidy.part-ab
# Update manifest.json clang_tidy_linux block, then:
git add prebuilt-binaries/clang-tidy.part-* manifest.json
git commit -m "vendor: update clang-tidy linux binary to LLVM 23.x.x"
git push
```

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | **Start here** — orchestrates the full build and install |
| `manifest.json` | SHA256 pins for all vendored archives and binaries |
| `llvm-src/*.part-*` | Vendored LLVM 22.1.1 source (split, committed) |
| `ninja-src/ninja-1.13.2.tar.gz` | Vendored Ninja source (committed) |
| `prebuilt-binaries/clang-format-linux` | Built output — generated, not committed |
| `prebuilt-binaries/clang-tidy-linux` | Assembled from parts — generated, not committed |
| `prebuilt-binaries/clang-tidy.part-aa` | Pre-built binary split part 1 (committed, ~52 MB) |
| `prebuilt-binaries/clang-tidy.part-ab` | Pre-built binary split part 2 (committed, ~31 MB) |
| `prebuilt-binaries/ninja-linux` | Built output — generated, not committed |
| `prebuilt-binaries/clang-format.exe` | Vendored pre-built binary (committed, 3.1 MB) |
| `prebuilt-binaries/clang-tidy.exe` | Vendored pre-built binary (committed, 46 MB) |
| `prebuilt-binaries/ninja.exe` | Vendored pre-built binary (committed) |
| `scripts/verify-clang-format-windows.sh` | Verify Windows clang-format.exe SHA256 |
| `scripts/verify-clang-tidy-windows.sh` | Verify Windows clang-tidy.exe SHA256 |
| `demo/` | clang-tidy demonstration — sample C++ file and runner |
| `docs/llvm-install-guide.md` | Prerequisites and troubleshooting |
| `scripts/build-clang-format.sh` | Compile clang-format from vendored source |
| `scripts/build-clang-tidy.sh` | Compile clang-tidy from vendored source (Windows + Linux) |
| `scripts/build-ninja.sh` | Compile Ninja from vendored source |
| `scripts/extract-llvm-source.sh` | Extract and restructure the LLVM tarball |
| `scripts/reassemble-clang-tidy.sh` | Verify parts + assemble Linux clang-tidy binary |
| `scripts/verify-sources.sh` | SHA256 check all vendored archives and binaries |
| `scripts/fetch-llvm-source.sh` | **[Maintainer]** Update vendored LLVM tarball |
| `scripts/split-llvm-tarball.sh` | **[Maintainer]** Split tarball for git hosting limits |