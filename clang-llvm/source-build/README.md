# clang-llvm-source-build

### Author: Nima Shafie

> **Optional** — builds `clang-format` and `clang-tidy` from LLVM source,
> or installs a pre-built `clang-tidy` binary (Linux only).
>
> Most developers should use the faster pip method for clang-format instead:
> ```bash
> bash clang-llvm-style-formatter/bootstrap.sh   # ~5 seconds
> ```

---

## When to Use This

| Scenario | Recommended method |
|----------|-------------------|
| Python 3.8+ available, clang-format only | `clang-llvm-style-formatter/bootstrap.sh` (pip) |
| Python unavailable | `clang-llvm-source-build/bootstrap.sh` (this) |
| Policy requires source builds | `clang-llvm-source-build/bootstrap.sh` (this) |
| Need clang-tidy (either platform) | `clang-llvm-source-build/bootstrap.sh` (this) |

---

## Usage

```bash
bash clang-llvm-source-build/bootstrap.sh
```

**On Linux**, this does two things:

1. Builds `clang-format` from the vendored LLVM 22.1.1 source (~30-60 min)
2. Installs `clang-tidy` from the vendored pre-built binary — reassembles
   the split parts and verifies SHA256 against `manifest.json` (seconds)

**On Windows**, this does two things:

1. Builds `clang-format` from the vendored LLVM 22.1.1 source (~30-60 min)
2. Builds `clang-tidy` from the same source tree incrementally (~60-120 min
   first run; subsequent runs skip already-compiled objects)

The binaries are placed at:

| Binary | Linux | Windows |
|--------|-------|---------|
| clang-format | `bin/linux/clang-format` | `bin/windows/clang-format.exe` |
| clang-tidy | `bin/linux/clang-tidy` | `bin/windows/clang-tidy.exe` |

`clang-llvm-style-formatter/bootstrap.sh` detects these binaries automatically.
After this script completes, run the formatter bootstrap to install the hook:

```bash
bash clang-llvm-style-formatter/bootstrap.sh
```

To force a full rebuild and re-verification:

```bash
bash clang-llvm-source-build/bootstrap.sh --rebuild
```

---

## Build Prerequisites

### Windows 11

| Tool | Minimum | Tested | Notes |
|------|---------|--------|-------|
| Visual Studio | 2017 any edition | VS Insiders 18 | "Desktop development with C++" workload required |
| MSVC toolchain | any | 14.50.35717 | Installed automatically with VS C++ workload |
| CMake | 3.14 | 4.1.2 | Bundled with VS 2019+; or install separately |
| Git Bash | any | MINGW64 | Run `bootstrap.sh` from Git Bash — not cmd.exe or PowerShell |

**VS environment is set up automatically** — you do not need to launch from
a "Developer Command Prompt". `build-clang-format.sh` and `build-clang-tidy.sh`
locate `cl.exe`, `link.exe`, and the Windows SDK automatically via `vswhere.exe`
and filesystem scan, then set `LIB`, `INCLUDE`, and `PATH` themselves.

Supported VS editions: Community, Professional, Enterprise, Build Tools,
Preview, Insiders — any edition that includes the VC++ tools workload.

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

### clang-format (source build, both platforms)

1. Checks for an existing binary — skips rebuild if found (use `--rebuild` to override)
2. Runs `scripts/build-ninja.sh` — builds Ninja from `ninja-src/` (~30 sec)
3. Runs `scripts/extract-llvm-source.sh` — reassembles the split tarball and extracts (~5-15 min)
4. Runs `scripts/build-clang-format.sh` — compiles with CMake + Ninja (~30-60 min)
5. Binary placed in `bin/<platform>/clang-format[.exe]`

### clang-tidy on Linux (pre-built vendored binary)

1. Checks for an existing binary — skips if found (use `--rebuild` to override)
2. Runs `scripts/reassemble-clang-tidy.sh`:
   - Verifies each split part against SHA256 in `manifest.json`
   - Reassembles `clang-tidy.part-aa` + `clang-tidy.part-ab` → `clang-tidy`
   - Verifies the assembled binary SHA256
   - Sets executable bit
3. Binary placed in `bin/linux/clang-tidy`

### clang-tidy on Windows (source build)

1. Checks for an existing binary — skips if found (use `--rebuild` to override)
2. Runs `scripts/build-clang-tidy.sh`:
   - Locates `cl.exe` via `vswhere.exe` or filesystem scan
   - Sets up MSVC + Windows SDK environment (`LIB`, `INCLUDE`, `PATH`)
   - Runs CMake configure with `-DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra"`
     (incremental reconfigure if `build/` already exists from clang-format)
   - Builds the `clang-tidy` target via Ninja (~60-120 min first run)
3. Binary placed in `bin/windows/clang-tidy.exe`

The Windows clang-tidy binary is **not committed to the repository** — it
is too large to vendor and is built locally from the same vendored LLVM source
that clang-format uses. The build directory is shared, so if clang-format was
already compiled the clang-tidy build is incremental.

---

## Using clang-tidy

After bootstrapping, the binary is at `bin/<platform>/clang-tidy[.exe]`.
A minimal usage example and a C++ file with intentional issues are in `demo/`:

```bash
bash clang-llvm-source-build/demo/run-demo.sh
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
rm -rf clang-llvm-source-build/llvm-src/build/
```

---

## Updating the Vendored LLVM Version (Maintainers Only)

On a machine with internet access:

```bash
bash clang-llvm-source-build/scripts/fetch-llvm-source.sh --version 23.x.x
bash clang-llvm-source-build/scripts/split-llvm-tarball.sh
git add clang-llvm-source-build/llvm-src/
git commit -m "vendor: update LLVM to 23.x.x"
git push
```

Developers rebuild with:
```bash
bash clang-llvm-source-build/bootstrap.sh --rebuild
```

## Updating the Vendored clang-tidy Linux Binary (Maintainers Only)

Build `clang-tidy` from LLVM source on a RHEL 8 x86_64 machine, then split
and update the manifest:

```bash
strip bin/linux/clang-tidy
split -b 52428800 bin/linux/clang-tidy bin/linux/clang-tidy.part-
sha256sum bin/linux/clang-tidy
sha256sum bin/linux/clang-tidy.part-aa bin/linux/clang-tidy.part-ab
# Update manifest.json clang_tidy_linux block, then:
git add bin/linux/clang-tidy.part-* manifest.json
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
| `bin/linux/clang-format` | Built output — generated, not committed |
| `bin/linux/clang-tidy` | Assembled from parts — generated, not committed |
| `bin/linux/clang-tidy.part-aa` | Pre-built binary split part 1 (committed, ~52 MB) |
| `bin/linux/clang-tidy.part-ab` | Pre-built binary split part 2 (committed, ~31 MB) |
| `bin/linux/ninja` | Built output — generated, not committed |
| `bin/windows/clang-format.exe` | Built output — generated, not committed |
| `bin/windows/clang-tidy.exe` | Built output — generated, not committed |
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