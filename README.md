# airgap-cpp-devkit

**Author: Nima Shafie**

Air-gapped C++ developer toolkit for network-restricted environments.

All tools work without internet access. All dependencies are vendored.
Tools install to system-wide or per-user paths depending on available privileges.

---

## Deployment Scenarios

This devkit supports two deployment scenarios depending on what your
air-gapped network permits.

### Base Case — Pre-built binaries allowed

The fastest path. Pre-built binaries are available via the
`prebuilt-binaries` submodule. No compiler, no Visual Studio, no CMake
required for most tools.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive
bash toolchains/clang/source-build/setup.sh
bash toolchains/clang/style-formatter/bootstrap.sh
```

### Worst Case — Binaries not permitted, source only

If your network prohibits pre-compiled binaries, skip the submodule and
build everything from the vendored source archives.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
# Do NOT run: git submodule update --init --recursive
bash toolchains/clang/source-build/setup.sh --build-from-source
bash toolchains/clang/style-formatter/bootstrap.sh
```

Each tool's bootstrap script detects which scenario applies and responds
accordingly. See [scripts/setup-prebuilt-submodule.sh](scripts/setup-prebuilt-submodule.sh)
for the interactive submodule setup helper.

---

## Install Modes

All bootstrap scripts detect whether the current user has admin/root
privileges and install to the appropriate path automatically.

| Mode | Windows | Linux |
|------|---------|-------|
| Admin (system-wide) | `C:\Program Files\airgap-cpp-devkit\<tool>\` | `/opt/airgap-cpp-devkit/<tool>/` |
| User (per-user) | `%LOCALAPPDATA%\airgap-cpp-devkit\<tool>\` | `~/.local/share/airgap-cpp-devkit/<tool>/` |

Admin mode is attempted first. If the current user cannot write to the
system path, user mode is used automatically with a clear warning printed
to the screen. An install receipt (`INSTALL_RECEIPT.txt`) and a timestamped
log file are always written regardless of install mode.

To install system-wide on Windows, right-click Git Bash and select
"Run as administrator" before running any bootstrap script.

---

## Tools

| Directory | Purpose | Required? |
|-----------|---------|-----------|
| [`toolchains/clang/style-formatter/`](toolchains/clang/style-formatter/README.md) | Enforces LLVM C++ coding standards via Git pre-commit hook | Yes |
| [`toolchains/clang/source-build/`](toolchains/clang/source-build/README.md) | Builds clang-format + clang-tidy from LLVM 22.1.2 source; installs pre-built binaries (Windows: instant, Linux: ~30-60 min) | No |
| [`cmake/`](cmake/README.md) | CMake 4.3.0 — build from source or install pre-built; RHEL 8 + Windows | No |
| [`dev-tools/git-bundle/`](dev-tools/git-bundle/README.md) | Transfers Git repositories with nested submodules across air-gapped boundaries | Yes |
| [`build-tools/lcov/`](build-tools/lcov/README.md) | Code coverage reporting via lcov 2.4 + gcov, vendored Perl deps included | No |
| [`python/`](python/README.md) | Portable Python 3.14.3 interpreter — Windows embeddable + Linux standalone (python-build-standalone) | No |
| [`dev-tools/vscode-extensions/`](dev-tools/vscode-extensions/README.md) | Offline VS Code extensions: C/C++, C++ TestMate, Python (win32-x64 + linux-x64) | No |
| [`toolchains/gcc/windows/`](toolchains/gcc/windows/README.md) | GCC 15.2.0 + MinGW-w64 13.0.0 UCRT toolchain for Windows | No — standalone |
| [`dev-tools/7zip/`](dev-tools/7zip/README.md) | 7-Zip 26.00 — admin + user install for Windows and Linux | No — standalone |
| [`dev-tools/servy/`](dev-tools/servy/README.md) | Servy 7.3 — Windows service manager (Windows only, graceful no-op on Linux) | No — standalone |
| [`frameworks/grpc/`](frameworks/grpc/README.md) | Vendored gRPC source build for Windows (v1.76.0 production-tested) | No — standalone |

---

## Optional Tools

All tools outside of `toolchains/clang/style-formatter/` and `dev-tools/git-bundle/` are
fully independent and optional. You can use any subset without affecting
the others.

**`python/`** installs a portable Python 3.14.3 that lives alongside any
existing system Python. It does not modify your PATH until you explicitly
run `source python/scripts/env-setup.sh`. Other devkit tools that require
Python will prefer this interpreter if active, and fall back to the system
Python if not.

**`dev-tools/vscode-extensions/`** installs offline VS Code extensions for C++
development. Requires VS Code to be installed and `code` on PATH.
Extensions are installed per-user into VS Code's extension directory.

**`cmake/`** provides CMake 4.3.0 for environments where the system CMake
is too old. On RHEL 8 the system CMake is 3.x — this module builds or
installs 4.3.0 into the devkit path without touching the system.

**`toolchains/gcc/windows/`** is a standalone GCC 15.2.0 + MinGW-w64
toolchain for developers who need to compile C++ projects in an air-gapped
Windows environment. It has no relationship to any other tool in this devkit.

**`dev-tools/7zip/`** provides 7-Zip 26.00 for environments that need `.7z`
archive support. Admin install uses the official silent installer (Windows)
or places `7zz` in `/usr/local/bin` (Linux). User install uses the portable
`7za.exe` (Windows) or `~/.local/bin/7zz` (Linux). No internet access or
package manager required.

**`dev-tools/servy/`** provides Servy 7.3, a Windows service manager that turns
any executable into a native Windows service with health checks, log rotation,
restart policies, and a full GUI + CLI + PowerShell interface. Requires 7-Zip
(`dev-tools/7zip/`) for extraction. Running `setup.sh` on Linux exits cleanly
with an informational message — no error.

**`frameworks/grpc/`** is a standalone gRPC source tree for teams that
need gRPC in their air-gapped C++ projects. The bash entry point
`setup_grpc.sh` handles admin detection and install path selection.

**`build-tools/lcov/`** provides code coverage reporting for C++ projects
compiled with GCC's `-fprofile-arcs -ftest-coverage` flags. Vendors lcov
2.4 and all required Perl dependencies — no CPAN, no EPEL required.

If you only need the formatter and git transfer tool, ignore everything else.

---

## Who Reads What

### I am a developer on a production C++ repository

Your repo already has the formatter set up. Run one command after cloning:

```bash
bash setup.sh
```

See your repo's `setup.sh` or [toolchains/clang/style-formatter/README.md](toolchains/clang/style-formatter/README.md)
for the full developer reference.

### I am a maintainer adding the formatter to a new production repo

See [Deploying to Production Repositories](#deploying-to-production-repositories) below.

### I am working on the devkit itself

See [Development Setup](#development-setup) below.

---

## Deploying to Production Repositories

> **Optional.** Only needed if you want to enforce LLVM C++ style in another
> repository using this devkit as a submodule. Skip this section entirely
> if you are only using the devkit tools directly.

The formatter lives as a submodule under `tools/` in each production repo.
Developers only ever run `bash setup.sh`.

**What lands in each production repo:**
```
your-cpp-project/
├── setup.sh                              <- ~50 lines, the only new root file
├── .gitmodules                           <- 3-line auto-generated pointer
└── tools/
    └── style-formatter/                  <- submodule (a commit pointer, not a copy)
```

### Step 1 — Add the submodule (once per repo)

```bash
cd your-cpp-project/

git submodule add \
    <airgap-cpp-devkit-repo-url> \
    tools/style-formatter

git submodule update --init --recursive
```

### Step 2 — Copy setup.sh into the repo root

```bash
cp tools/style-formatter/toolchains/clang/style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 — Append .gitignore entries

```bash
cat tools/style-formatter/toolchains/clang/style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### Step 4 — Commit and push

```bash
git add .gitmodules tools/style-formatter setup.sh .gitignore
git commit -m "chore: add LLVM C++ style enforcement"
git push
```

### What developers do after this (once per machine)

```bash
git clone <your-cpp-project-url>
cd your-cpp-project
bash setup.sh
```

Done. The hook is installed. Every subsequent `git commit` enforces LLVM style.

---

## Development Setup

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit

# Base case — initialize prebuilt-binaries submodule (if binaries are permitted)
bash scripts/setup-prebuilt-submodule.sh

# Install the formatter (fast, ~5 seconds)
bash toolchains/clang/style-formatter/bootstrap.sh
```

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Git Bash (MINGW64) |
| RHEL 8 | Bash 4.x |

No compiler, no Visual Studio, no CMake required for the standard install.
See each tool's README for source-build prerequisites.

### Install methods

**Method 1 — pip/venv for clang-format (recommended, ~5 seconds)**
```bash
bash toolchains/clang/style-formatter/bootstrap.sh
```
Installs `clang-format` from a vendored `.whl` file into a local Python venv.
No network access. No compiler. No admin rights required (installs in-repo).

**Method 2 — clang-format + clang-tidy from vendored binaries (base case)**
```bash
bash scripts/setup-prebuilt-submodule.sh
bash toolchains/clang/source-build/setup.sh
```
Verifies and installs pre-built binaries from the `prebuilt-binaries`
submodule. Windows: instant. Linux: reassembles clang-tidy from split parts.

**Method 3 — Build from LLVM source (worst case / policy requirement)**
```bash
bash toolchains/clang/source-build/setup.sh --build-from-source
```
Compiles `clang-format` and `clang-tidy` from the vendored LLVM 22.1.2
source tarball (~30-120 minutes). Use when pre-built binaries are not
permitted or Python is unavailable.
Requires: Visual Studio 2022 (Windows) or GCC 8+ (Linux). CMake 3.14+.

**Method 4 — CMake 4.3.0**
```bash
bash cmake/bootstrap.sh
# or build from source:
bash cmake/bootstrap.sh --build-from-source
```
Installs CMake 4.3.0 to the devkit path. Required for RHEL 8 environments
where the system CMake is too old for modern C++ projects.

**Method 5 — Portable Python 3.14.3**
```bash
bash python/bootstrap.sh
source python/scripts/env-setup.sh
```
Installs a self-contained Python 3.14.3 alongside any existing system Python.
Does not affect system Python until `env-setup.sh` is sourced.

**Method 6 — VS Code extensions (offline)**
```bash
bash dev-tools/vscode-extensions/setup.sh
```
Installs C/C++, C++ TestMate, and Python extensions into VS Code offline.
Requires VS Code installed and `code` on PATH.

**Method 7 — GCC toolchain for Windows**
```bash
cd toolchains/gcc/windows
bash setup.sh x86_64
source scripts/env-setup.sh x86_64
```
Installs GCC 15.2.0 + MinGW-w64 13.0.0 UCRT. Only needed if you require
GCC to compile C++ projects on Windows.

**Method 8 — 7-Zip 26.00 (Windows + Linux)**
```bash
bash dev-tools/7zip/setup.sh
```
Installs 7-Zip 26.00. Admin mode: system-wide install. User mode: portable
drop-in with no elevation required. Supports `.7z`, `.zip`, `.tar.xz`, and
all major archive formats on both Windows and Linux.

**Method 9 — Servy 7.3 (Windows service manager)**
```bash
bash dev-tools/servy/setup.sh
```
Installs Servy 7.3 portable — GUI, Manager app, CLI, and PowerShell module.
Turns any executable into a native Windows service with health checks, log
rotation, and restart policies. Admin: `C:\Program Files\servy\`. User:
`%LOCALAPPDATA%\airgap-cpp-devkit\servy\`. Requires 7-Zip first. Windows only.

**Method 10 — gRPC for Windows**
```bash
cd frameworks/grpc
bash setup_grpc.sh
```
Builds gRPC from vendored source using MSVC + CMake.
Requires: Visual Studio 2022 with Desktop C++ workload, Git Bash.

**Method 11 — lcov code coverage (RHEL 8 / Linux)**
```bash
bash build-tools/lcov/setup.sh
source build-tools/lcov/scripts/env-setup.sh
```
Installs lcov 2.4 and all Perl dependencies from vendored tarballs.
No internet access, no CPAN, no EPEL required.

---

## Design Principles

| Principle | How it is met |
|-----------|--------------|
| Air-gapped | All dependencies vendored in-repo or in prebuilt-binaries submodule |
| Binary-restricted environments | Skip prebuilt-binaries submodule; build all tools from vendored source |
| Admin + user install support | Admin detection at runtime; system-wide or per-user install paths |
| Install transparency | Install receipt + timestamped log file written on every bootstrap |
| Minimal production footprint | One `setup.sh` + one submodule pointer per production repo |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Single entry point per tool | `bash bootstrap.sh` or `bash setup.sh` — nothing else required |
| Integrity verification | SHA256 pinned in `manifest.json` for all vendored archives and binaries |
| No personal URLs | All SBOM namespaces use `airgap-cpp-devkit.internal` — safe for internal distribution |

---

## Repository Structure

```
airgap-cpp-devkit/
├── README.md                              <- you are here
├── sbom.spdx.json                         <- root aggregate SBOM (SPDX 2.3)
├── install.sh                             <- top-level orchestrator
├── uninstall.sh                           <- removes all installed tools
├── .gitmodules                            <- prebuilt-binaries submodule pointer
│
├── scripts/
│   ├── install-mode.sh                    <- shared admin/user detection library
│   ├── setup-prebuilt-submodule.sh        <- initialize prebuilt-binaries submodule
│   └── generate-sbom.sh                   <- regenerates all SBOM timestamps
│
├── prebuilt-binaries/                     <- SUBMODULE (separate repo, optional)
│   │                                         Skip entirely in binary-restricted envs
│   ├── toolchains/clang/
│   │   ├── clang-format.exe
│   │   ├── clang-tidy.exe
│   │   ├── clang-tidy.part-aa
│   │   └── clang-tidy.part-ab
│   ├── winlibs-gcc-ucrt/
│   │   └── *.zip.part-*                   <- GCC toolchain split parts
│   └── 7zip/
│       ├── 7z2600-x64.exe                 <- Windows admin installer
│       ├── 7z2600-extra.7z                <- Windows portable (7za.exe)
│       └── 7z2600-linux-x64.tar.xz        <- Linux 7zz binary
│   └── servy/
│       ├── servy-7.3-x64-portable.7z.part-aa   <- ~50 MB
│       └── servy-7.3-x64-portable.7z.part-ab   <- ~30 MB
│
├── toolchains/clang/                            <- LLVM/Clang tooling group
│   ├── style-formatter/                   <- LLVM style enforcement tool
│   │   ├── bootstrap.sh
│   │   ├── sbom.spdx.json
│   │   ├── python-packages/               <- vendored .whl files
│   │   ├── config/
│   │   │   ├── .clang-format
│   │   │   ├── .clang-tidy
│   │   │   └── hooks.conf
│   │   ├── hooks/pre-commit
│   │   ├── scripts/
│   │   └── docs/
│   │       ├── gitignore-snippet.txt
│   │       └── production-repo-template/
│   │           ├── setup.sh
│   │           └── README.md
│   │
│   └── source-build/                      <- clang-format + clang-tidy build/install
│       ├── bootstrap.sh
│       ├── manifest.json
│       ├── sbom.spdx.json
│       ├── llvm-src/                      <- vendored LLVM 22.1.2 (split parts)
│       ├── ninja-src/                     <- vendored Ninja 1.13.2
│       ├── bin/
│       │   ├── windows/
│       │   └── linux/
│       └── scripts/
│
├── cmake/                                 <- CMake 4.3.0
│   ├── bootstrap.sh
│   ├── manifest.json
│   └── vendor/                            <- vendored source tarball (split parts)
│
├── dev-tools/git-bundle/                            <- air-gap git transfer tool
│   ├── bundle.py
│   ├── export.py
│   ├── sbom.spdx.json
│   └── tests/
│
├── build-tools/lcov/                     <- code coverage reporting (Linux)
│   ├── bootstrap.sh
│   ├── manifest.json
│   ├── sbom.spdx.json
│   ├── scripts/
│   └── vendor/
│       ├── lcov-2.4.tar.gz
│       └── perl-libs.tar.gz
│
├── python/                                <- portable Python 3.14.3
│   ├── bootstrap.sh
│   ├── manifest.json
│   ├── sbom.spdx.json
│   ├── README.md
│   ├── scripts/
│   │   ├── verify.sh
│   │   └── env-setup.sh
│   └── vendor/
│       ├── python-3.14.3-embed-amd64.zip              <- Windows (~12MB)
│       ├── cpython-3.14.3+...linux-gnu...part-aa      <- Linux split part (~100MB)
│       └── cpython-3.14.3+...linux-gnu...part-ab      <- Linux split part (~19MB)
│
├── dev-tools/vscode-extensions/                     <- offline VS Code extensions
│   ├── bootstrap.sh
│   ├── manifest.json
│   ├── sbom.spdx.json
│   ├── README.md
│   └── vendor/
│       ├── ms-vscode.cpptools-extension-pack-1.5.1.vsix
│       ├── ms-vscode.cpptools-1.30.4-win32-x64.vsix.part-*
│       ├── ms-vscode.cpptools-1.30.4-linux-x64.vsix.part-*
│       ├── matepek.vscode-catch2-test-adapter-4.22.3.vsix
│       ├── ms-python.python-2026.5...-win32-x64.vsix
│       └── ms-python.python-2026.5...-linux-x64.vsix
│
├── prebuilt/                              <- prebuilt tools (scripts + manifests only)
│   ├── winlibs-gcc-ucrt/                  <- GCC 15.2.0 + MinGW-w64 13.0.0 UCRT
│   │   ├── setup.sh
│   │   ├── manifest.json
│   │   ├── sbom.spdx.json
│   │   └── scripts/
│   └── 7zip/                              <- 7-Zip 26.00 (Windows + Linux)
│       ├── setup.sh
│       ├── manifest.json
│       ├── sbom.spdx.json
│       ├── README.md
│       └── scripts/
│           ├── verify.sh
│           ├── install-windows.sh
│           └── install-linux.sh
│   └── servy/                             <- Servy 7.3 (Windows service manager)
│       ├── setup.sh
│       ├── manifest.json
│       ├── sbom.spdx.json
│       ├── README.md
│       └── scripts/
│           ├── verify.sh
│           ├── install-windows.sh
│           └── install-linux.sh           <- graceful no-op on Linux
│
└── frameworks/grpc/                     <- gRPC source build (Windows)
    ├── setup_grpc.sh
    ├── setup_grpc.bat
    ├── manifest.json
    ├── sbom.spdx.json
    ├── README.md
    ├── scripts/
    └── vendor/
        └── grpc-1.76.0.tar.gz.part-aa
```