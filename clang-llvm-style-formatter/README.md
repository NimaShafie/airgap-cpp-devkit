# clang-llvm-style-formatter

> Pre-commit hook enforcement of the [LLVM Coding Standards](https://llvm.org/docs/CodingStandards.html)
> for C/C++ repositories — designed for air-gapped, multi-repo, multi-platform environments.

---

## Overview

`clang-llvm-style-formatter` is a **self-contained Git submodule** that enforces
LLVM C++ style via a pre-commit hook.

The submodule ships with everything needed to build `clang-format` and `ninja`
from source, with no network access required on developer machines:

- **`llvm-src/llvm-project-22.1.1.src.tar.xz`** — the LLVM/Clang source tarball (~159 MB, committed)
- **`ninja-src/ninja-1.13.2.tar.gz`** — the Ninja build system source (~220 KB, committed)

Developers clone the repo, run `bootstrap.sh`, and everything is built locally.

```
your-repo/
├── .git/hooks/pre-commit          ← installed by bootstrap.sh
└── .llvm-hooks/                   ← this submodule
    ├── bootstrap.sh               ← ONE command to set up everything
    ├── llvm-src/
    │   └── llvm-project-22.1.1.src.tar.xz   ← committed source tarball
    ├── ninja-src/
    │   └── ninja-1.13.2.tar.gz              ← committed ninja source
    ├── bin/
    │   ├── linux/clang-format     ← built on developer machine (not committed)
    │   ├── linux/ninja            ← built if needed (not committed)
    │   ├── windows/clang-format.exe  ← built on developer machine (not committed)
    │   └── windows/ninja.exe      ← built if needed (not committed)
    ├── config/
    │   ├── .clang-format          ← LLVM style rules
    │   ├── .clang-tidy            ← static analysis rules
    │   └── hooks.conf             ← runtime toggles
    ├── hooks/pre-commit           ← the gate logic
    └── scripts/
        ├── extract-llvm-source.sh ← extracts the committed tarball
        ├── build-clang-format.sh  ← compiles clang-format
        ├── build-ninja.sh         ← compiles ninja from vendored source
        ├── fetch-llvm-source.sh   ← [MAINTAINER] update vendored tarball
        ├── install-hooks.sh
        ├── fix-format.sh
        ├── verify-tools.sh
        ├── find-tools.sh
        ├── setup-user-path.sh
        └── create-test-repo.sh
```

---

## Developer Workflow

### Adding to a new host repository (once per repo)

```bash
git submodule add https://bitbucket.example.com/your-org/clang-llvm-style-formatter.git .llvm-hooks
git submodule update --init --recursive
bash .llvm-hooks/bootstrap.sh
git add .gitmodules .llvm-hooks .clang-format .clang-tidy
git commit -m "chore: add LLVM style enforcement"
```

### After cloning a repo that already has this submodule

```bash
bash .llvm-hooks/bootstrap.sh
```

That's it. Bootstrap handles everything:

| Step | What happens |
|------|-------------|
| 1 | Git submodules initialised |
| 2 | Scans system PATH for `clang-format` and `ninja` — reports what was found and what was missing |
| 3 | If anything is missing: shows what will be built and asks **"Install from vendored source? [y/N]"** |
| → | **Yes** → builds missing tools from the committed tarballs (no network needed) |
| → | **No** → exits with an error; the hook is NOT installed |
| → | `build-ninja.sh` builds Ninja first (~30 sec) |
| → | `extract-llvm-source.sh` extracts the LLVM tarball (~5–15 min) |
| → | `build-clang-format.sh` compiles `clang-format` (~30–60 min) |
| 4 | Pre-commit hook installed into `.git/hooks/pre-commit` |

**No network access is required at any point on developer machines.**

---

## Build Prerequisites

The build requires tools already present on a standard developer machine.
`clang-format` itself does not need to be pre-installed.

### Windows 11 (Git Bash / MINGW64)

| Tool | Minimum | Notes |
|------|---------|-------|
| Visual Studio | 2017 / 2019 / 2022 | With C++ workload |
| CMake | 3.14 | Bundled with VS 2019+ |
| Python 3 | 3.6 | Bundled with VS 2019+ |

Run `bootstrap.sh` from an **x64 Native Tools Command Prompt for VS**, or from
Git Bash after sourcing the VS environment.

Ninja is vendored in `ninja-src/` — no separate Ninja installation needed.

### RHEL 8

| Tool | Package | Minimum |
|------|---------|---------|
| GCC/G++ | `gcc-c++` | 8.x |
| CMake | `cmake` | 3.14 |
| Python 3 | pre-installed | 3.6 |

Ninja is vendored in `ninja-src/` — no separate Ninja installation needed.

See `docs/llvm-install-guide.md` for detailed prerequisite instructions and
troubleshooting.

---

## How the Pre-Commit Hook Works

On every `git commit`, the hook:

1. Collects all staged C/C++ files (`.cpp`, `.cxx`, `.cc`, `.c`, `.h`, `.hpp`, `.hxx`, `.hh`)
2. Runs `clang-format --style=file` against the staged content
3. Rejects the commit if any file would be reformatted

When a commit is rejected:

```
╔══════════════════════════════════════════════════════════════════╗
║  clang-format: LLVM style violations found — commit REJECTED    ║
╚══════════════════════════════════════════════════════════════════╝
    ✗  src/bad_indent.cpp

  Fix options:
    Auto-fix staged files:  .llvm-hooks/scripts/fix-format.sh
    Manual:                 clang-format --style=file -i <file>
```

### Auto-fixing violations

```bash
bash .llvm-hooks/scripts/fix-format.sh        # fix and re-stage
bash .llvm-hooks/scripts/fix-format.sh --dry-run  # preview only
git commit -m "your message"
```

### Emergency bypass

```bash
git commit --no-verify -m "emergency"
```

---

## Configuration

### Per-repo overrides

`bootstrap.sh` creates `.llvm-hooks-local/hooks.conf` for per-repo settings:

```bash
# Enable clang-tidy (requires compile_commands.json from CMake)
ENABLE_TIDY="true"

# Use a system-installed clang-format instead of the vendored build
CLANG_FORMAT_BIN="/usr/bin/clang-format-17"

# Show per-file diffs when a commit is rejected
VERBOSE="true"
```

### Style rules

Edit `config/.clang-format` and `config/.clang-tidy` in this submodule.
All host repos pick up changes on the next `git submodule update --remote .llvm-hooks`.

---

## Known Issues — Windows (Git Bash / MINGW64)

### Symlink warnings during tarball extraction

The LLVM tarball contains Linux symlinks inside `test/` directories. Windows
cannot create these. `extract-llvm-source.sh` suppresses the warnings — they
are harmless because `test/` directories are stripped immediately after.

Expected (harmless) output during extraction:
```
tar: .../clang/test/Driver/Inputs/...: Cannot create symlink to '...': No such file or directory
```

### "Device or resource busy" when clearing llvm-src/

Git Bash holds a handle on tracked directories. `extract-llvm-source.sh`
works around this by deleting the **contents** of `llvm-src/` rather than
the directory itself. If the error persists, close all File Explorer windows,
terminals, and editors that have `llvm-src/` open, then rerun.

---

## Updating the Submodule in Host Repositories

```bash
git submodule update --remote .llvm-hooks
git add .llvm-hooks
git commit -m "chore: update clang-llvm-style-formatter"
```

---

## Updating the Vendored LLVM Version (Maintainers Only)

```bash
# On a connected machine:
bash scripts/fetch-llvm-source.sh --version 23.x.x

# Or with a pre-downloaded tarball:
bash scripts/fetch-llvm-source.sh \
    --version 23.x.x \
    --tarball-dir /path/to/downloads

# Commit and push:
git add llvm-src/llvm-project-23.x.x.src.tar.xz
git commit -m "vendor: update LLVM tarball to 23.x.x"
git push
```

Developers get the new tarball on the next `git pull` and rebuild with
`bash .llvm-hooks/scripts/build-clang-format.sh --rebuild`.

---

## Air-Gapped Environments

No network access is required on developer machines. The committed tarballs
(`llvm-src/llvm-project-22.1.1.src.tar.xz` and `ninja-src/ninja-1.13.2.tar.gz`)
contain everything needed. Everything is compiled locally from those sources.

The only step requiring network access is the one-time maintainer operation
of updating the vendored tarball (`fetch-llvm-source.sh`), which is run on
a connected machine before committing and distributing.

---

## Supported Environments

| Environment | Status |
|-------------|--------|
| Windows 11 + Git Bash (MINGW64) | ✓ Supported |
| RHEL 8 + Bash 4.x | ✓ Supported |
| VxWorks Workbench (Eclipse) | Hook runs on host OS shell; VxWorks target unaffected |
| Visual Studio 2017 / 2019 / 2022 | IDE-independent; hook runs via Git |
| C++11 / C++14 / C++17 code | ✓ `.clang-format` uses `Standard: Auto` |

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | One-command developer setup |
| `hooks/pre-commit` | Pre-commit gate logic |
| `config/hooks.conf` | Runtime configuration |
| `config/.clang-format` | LLVM clang-format style rules |
| `config/.clang-tidy` | LLVM clang-tidy checks |
| `llvm-src/llvm-project-22.1.1.src.tar.xz` | Vendored LLVM source (~159 MB, committed) |
| `ninja-src/ninja-1.13.2.tar.gz` | Vendored Ninja source (~220 KB, committed) |
| `bin/linux/clang-format` | Built binary — generated, not committed |
| `bin/linux/ninja` | Built binary — generated, not committed |
| `bin/windows/clang-format.exe` | Built binary — generated, not committed |
| `bin/windows/ninja.exe` | Built binary — generated, not committed |
| `scripts/extract-llvm-source.sh` | Extract the committed LLVM tarball |
| `scripts/build-clang-format.sh` | Compile clang-format |
| `scripts/build-ninja.sh` | Compile Ninja from vendored source |
| `scripts/fetch-llvm-source.sh` | **[Maintainer]** Update vendored LLVM tarball |
| `scripts/install-hooks.sh` | Wire hook into a host repo |
| `scripts/fix-format.sh` | Auto-format and re-stage failing files |
| `scripts/verify-tools.sh` | Tool diagnostic with build guidance |
| `scripts/find-tools.sh` | Sourced helper: discover clang-format |
| `scripts/create-test-repo.sh` | End-to-end isolated test harness |
| `docs/llvm-install-guide.md` | Build prerequisites by platform |