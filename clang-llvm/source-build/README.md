# clang-llvm-source-build

### Author: Nima Shafie

> **Optional** — builds `clang-format` from LLVM source (~30-60 minutes).
>
> Most developers should use the faster pip method instead:
> ```bash
> bash clang-llvm-style-formatter/bootstrap.sh   # ~5 seconds
> ```

---

## When to Use This

| Scenario | Recommended method |
|----------|-------------------|
| Python 3.8+ available | `clang-llvm-style-formatter/bootstrap.sh` (pip) |
| Python unavailable | `clang-llvm-source-build/bootstrap.sh` (this) |
| Policy requires source builds | `clang-llvm-source-build/bootstrap.sh` (this) |

---

## Usage

```bash
bash clang-llvm-source-build/bootstrap.sh
```

The compiled binary is placed at:
- `bin/windows/clang-format.exe` (Windows)
- `bin/linux/clang-format` (Linux)

`clang-llvm-style-formatter/bootstrap.sh` detects this binary automatically.
After the source build completes, run the formatter bootstrap to install the hook:

```bash
bash clang-llvm-style-formatter/bootstrap.sh
```

To force a rebuild:

```bash
bash clang-llvm-source-build/bootstrap.sh --rebuild
```

---

## Build Prerequisites

### Windows 11

| Tool | Minimum | Notes |
|------|---------|-------|
| Visual Studio | 2017 / 2019 / 2022 / Insider | With "Desktop development with C++" workload |
| CMake | 3.14+ | Bundled with VS 2019+ |
| Git Bash | Any | Run bootstrap from Git Bash, not cmd.exe |

### RHEL 8

```bash
sudo dnf install gcc-c++ cmake python3
```

See [`docs/llvm-install-guide.md`](docs/llvm-install-guide.md) for detailed
instructions, troubleshooting, and known platform issues.

---

## How It Works

1. Checks for an existing binary — skips rebuild if found (use `--rebuild` to override)
2. Runs `scripts/build-ninja.sh` — builds Ninja from `ninja-src/` (~30 sec)
3. Runs `scripts/extract-llvm-source.sh` — reassembles the split tarball and extracts (~5-15 min)
4. Runs `scripts/build-clang-format.sh` — compiles clang-format with CMake + Ninja (~30-60 min)
5. Binary output placed in `bin/<platform>/clang-format[.exe]`

---

## Updating the Vendored LLVM Version (Maintainers Only)

On a machine with internet access:

```bash
# Download new tarball
bash clang-llvm-source-build/scripts/fetch-llvm-source.sh --version 23.x.x

# Split for git hosting file size limits (GitHub: 100 MB max)
bash clang-llvm-source-build/scripts/split-llvm-tarball.sh

git add clang-llvm-source-build/llvm-src/
git commit -m "vendor: update LLVM to 23.x.x"
git push
```

Developers rebuild with:
```bash
bash clang-llvm-source-build/bootstrap.sh --rebuild
```

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | **Start here** — orchestrates the full build |
| `llvm-src/*.part-*` | Vendored LLVM 22.1.1 source (split, committed) |
| `ninja-src/ninja-1.13.2.tar.gz` | Vendored Ninja source (committed) |
| `bin/windows/clang-format.exe` | Built output — generated, not committed |
| `bin/linux/clang-format` | Built output — generated, not committed |
| `docs/llvm-install-guide.md` | Prerequisites and troubleshooting |
| `scripts/build-clang-format.sh` | Compile clang-format from vendored source |
| `scripts/build-ninja.sh` | Compile Ninja from vendored source |
| `scripts/extract-llvm-source.sh` | Extract and restructure the LLVM tarball |
| `scripts/fetch-llvm-source.sh` | **[Maintainer]** Update vendored LLVM tarball |
| `scripts/split-llvm-tarball.sh` | **[Maintainer]** Split tarball for git hosting limits |