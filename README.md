# airgap-cpp-devkit

**Author: Nima Shafie**

Air-gapped C++ developer toolkit for network-restricted environments.

All tools work without internet access. All dependencies are vendored.
Tools install to system-wide or per-user paths depending on available privileges.

---

## Quick Start

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive
bash launch.sh
```

`launch.sh` starts the **DevKit Manager** — a local web UI for installing and
managing all devkit tools. It finds Python on your machine, starts the server,
and opens `http://127.0.0.1:8080` in your browser automatically.

Once the browser opens:

1. Pick a **profile** to install a curated set in one click (recommended):
   - **C++ Developer** — clang, cmake, python, conan, VS Code extensions, sqlite, 7zip
   - **DevOps** — cmake, python, conan, sqlite, 7zip
   - **Minimal** — required tools only (clang, cmake, python, style-formatter)
   - **Full** — everything
2. Or click **Install** next to individual tools to install them one at a time.
3. Live output streams directly in the terminal panel on the right.

> **No Python 3.8+?** `launch.sh` automatically falls back to the CLI wizard.
> You can also run it directly: `bash install.sh`
> Use `install.sh` for headless/CI installs (`--yes --profile cpp-dev`) or when no browser is available.

---

## Deployment Scenarios

### Base Case -- Pre-built binaries allowed

Pre-built binaries are available via the `prebuilt-binaries` submodule.
No compiler, no Visual Studio, no CMake required for most tools.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive
bash launch.sh          # preferred: opens DevKit Manager in browser
# or: bash install.sh   # CLI fallback
```

The launcher (and `install.sh`) detect the submodule and use prebuilt
binaries automatically. For toolchains that need source builds (e.g. clang
on Linux), the scripts handle those steps transparently.

### Worst Case -- Binaries not permitted, source only

If your network prohibits pre-compiled binaries, skip the submodule entirely.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
# Do NOT run: git submodule update --init --recursive
bash launch.sh          # preferred: opens DevKit Manager in browser
# or: bash install.sh   # CLI fallback
```

Both the DevKit Manager and `install.sh` detect that the submodule is absent
and fall back to building all tools from vendored source archives automatically.

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
"Run as administrator" before running `install.sh`.

---

## Tools

| Directory | Purpose | Required? |
|-----------|---------|-----------|
| [`toolchains/clang/style-formatter/`](toolchains/clang/style-formatter/README.md) | Enforces LLVM C++ coding standards via Git pre-commit hook | Yes |
| [`toolchains/clang/source-build/`](toolchains/clang/source-build/README.md) | Builds clang-format + clang-tidy from LLVM 22.1.2 source; installs pre-built binaries (Windows: instant, Linux: ~30-60 min) | No |
| [`build-tools/cmake/`](build-tools/cmake/README.md) | CMake 4.3.1 -- build from source or install pre-built; RHEL 8 + Windows | No |
| [`dev-tools/git-bundle/`](dev-tools/git-bundle/README.md) | Transfers Git repositories with nested submodules across air-gapped boundaries | Yes |
| [`dev-tools/devkit-ui/`](dev-tools/devkit-ui/README.md) | Web-based package manager GUI for installing and managing devkit tools (FastAPI + HTMX) | No |
| [`build-tools/lcov/`](build-tools/lcov/README.md) | Code coverage reporting via lcov 2.4 + gcov, vendored Perl deps included | No |
| [`languages/python/`](languages/python/README.md) | Portable Python 3.14.4 interpreter -- Windows embeddable + Linux standalone | No |
| [`languages/dotnet/`](languages/dotnet/README.md) | Portable .NET 10 SDK 10.0.201 -- Windows + Linux, no installer required | No |
| [`dev-tools/vscode-extensions/`](dev-tools/vscode-extensions/README.md) | Offline VS Code extensions: C/C++, C++ TestMate, Python (win32-x64 + linux-x64) | No |
| [`toolchains/gcc/windows/`](toolchains/gcc/windows/README.md) | GCC 15.2.0 + MinGW-w64 13.0.0 UCRT toolchain for Windows | No -- standalone |
| [`dev-tools/7zip/`](dev-tools/7zip/README.md) | 7-Zip 26.00 -- admin + user install for Windows and Linux | No -- standalone |
| [`dev-tools/servy/`](dev-tools/servy/README.md) | Servy 7.8 -- Windows service manager (Windows only, graceful no-op on Linux) | No -- standalone |
| [`dev-tools/conan/`](dev-tools/conan/README.md) | Conan 2.27.0 -- C/C++ package manager, Windows + Linux, no Python required | No -- standalone |
| [`frameworks/grpc/`](frameworks/grpc/README.md) | gRPC v1.78.1 for Windows -- prebuilt install (instant) or full source build (~40 min) | No -- standalone |

---

## Optional Tools

All tools outside of `toolchains/clang/style-formatter/` and `dev-tools/git-bundle/` are
fully independent and optional. You can use any subset without affecting the others.

**`languages/python/`** installs a portable Python 3.14.4 that lives alongside any
existing system Python. It does not modify your PATH until you explicitly
run `source languages/python/scripts/env-setup.sh`. Other devkit tools that require
Python will prefer this interpreter if active, and fall back to the system
Python if not. Includes 10 vendored pip packages installed offline.

**`languages/dotnet/`** installs a portable .NET 10 SDK 10.0.201 that lives alongside
any existing system .NET installation. No installer, no registry changes, no elevation
required for user install. Includes the C# 14 compiler, .NET Runtime, ASP.NET Core
Runtime, MSBuild, NuGet client, and the full `dotnet` CLI. Supports building and
publishing self-contained executables for Windows and Linux.

**`dev-tools/vscode-extensions/`** installs offline VS Code extensions for C++
development. Requires VS Code to be installed and `code` on PATH.
Extensions are installed per-user into VS Code's extension directory.

**`build-tools/cmake/`** provides CMake 4.3.1 for environments where the system CMake
is too old. On RHEL 8 the system CMake is 3.x -- this module builds or
installs 4.3.1 into the devkit path without touching the system.

**`toolchains/gcc/windows/`** is a standalone GCC 15.2.0 + MinGW-w64
toolchain for developers who need to compile C++ projects in an air-gapped
Windows environment. It has no relationship to any other tool in this devkit.

**`dev-tools/7zip/`** provides 7-Zip 26.00 for environments that need `.7z`
archive support. Admin install uses the official silent installer (Windows)
or places `7zz` in `/usr/local/bin` (Linux). User install uses the portable
`7za.exe` (Windows) or `~/.local/bin/7zz` (Linux). No internet access or
package manager required.

**`dev-tools/servy/`** provides Servy 7.8, a Windows service manager that turns
any executable into a native Windows service with health checks, log rotation,
restart policies, and a full GUI + CLI + PowerShell interface. Requires 7-Zip
(`dev-tools/7zip/`) for extraction. Running `setup.sh` on Linux exits cleanly
with an informational message -- no error.

**`dev-tools/conan/`** provides Conan 2.27.0, the open-source C/C++ package manager.
Self-contained executables for Windows and Linux -- no Python runtime required.
Pairs with CMake via `CMakeDeps` and `CMakeToolchain` generators. Supports
air-gap workflows via `conan cache save` / `conan cache restore`.

**`frameworks/grpc/`** provides gRPC v1.78.1 for air-gapped Windows C++ development.
Two paths are available: install from prebuilt in seconds using
`install-prebuilt.ps1`, or build from the vendored recursive source bundle
using `setup.ps1` (~40 minutes, MSVC required). Both paths produce an
identical install layout. A HelloWorld demo (greeter server + client) is
built and launched automatically to verify the installation end-to-end.

**`dev-tools/devkit-ui/`** is the preferred way to install and manage devkit tools.
Started automatically by `bash launch.sh`. Provides a visual dashboard of all tools
with installed/not-installed status, one-click install and rebuild per tool,
profile-based batch installs, and a log browser with inline viewer.
Requires Python 3.8+ (system Python). Dependencies (FastAPI, uvicorn, HTMX) are
auto-installed on first launch; in air-gapped environments pre-download wheels to
`dev-tools/devkit-ui/vendor/` and the launcher uses them automatically.

```bash
bash launch.sh                     # preferred: auto-finds Python, opens UI
bash launch.sh --port 9090         # custom port
bash launch.sh --no-browser        # server only, no auto-open
bash launch.sh --cli               # skip UI, use install.sh instead
```

**`build-tools/lcov/`** provides code coverage reporting for C++ projects
compiled with GCC's `-fprofile-arcs -ftest-coverage` flags. Vendors lcov
2.4 and all required Perl dependencies -- no CPAN, no EPEL required.

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
+-- setup.sh                              <- ~50 lines, the only new root file
+-- .gitmodules                           <- 3-line auto-generated pointer
+-- tools/
    +-- style-formatter/                  <- submodule (a commit pointer, not a copy)
```

### Step 1 -- Add the submodule (once per repo)

```bash
cd your-cpp-project/

git submodule add \
    <airgap-cpp-devkit-repo-url> \
    tools/style-formatter

git submodule update --init --recursive
```

### Step 2 -- Copy setup.sh into the repo root

```bash
cp tools/style-formatter/toolchains/clang/style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 -- Append .gitignore entries

```bash
cat tools/style-formatter/toolchains/clang/style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### Step 4 -- Commit and push

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

# Base case -- initialize prebuilt-binaries submodule (if binaries are permitted)
bash scripts/setup-prebuilt-submodule.sh

# Launch DevKit Manager (preferred)
bash launch.sh
```

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Git Bash (MINGW64), Python 3.8+ |
| RHEL 8 | Bash 4.x, Python 3.8+ |

Python is required for the DevKit Manager. It is pre-installed on all supported
platforms. The CLI fallback (`install.sh`) requires only Bash.

No compiler, no Visual Studio, no CMake required for the standard install.
See each tool's README for source-build prerequisites.

### Install methods

**Preferred -- DevKit Manager (web UI)**
```bash
bash launch.sh
```
Detects Python, starts a local server, opens `http://127.0.0.1:8080` in your
browser. Use the profile buttons for one-click batch installs, or install tools
individually. Live output streams to the terminal. Fallback to `install.sh`
if Python is unavailable.

```bash
bash launch.sh --port 9090        # custom port
bash launch.sh --host 0.0.0.0     # LAN / remote access
bash launch.sh --no-browser       # headless mode
bash launch.sh --cli              # force CLI installer
```

---

**CLI Installer**

All methods below are also accessible from the DevKit Manager UI.
Use these for scripting, CI, or when Python is unavailable.

**Method 1 -- Full install via install.sh**
```bash
bash install.sh
```
Interactive wizard. Detects platform, prompts for optional tools, installs
everything in the correct order.

**Method 2 -- pip/venv for clang-format only (~5 seconds)**
```bash
bash toolchains/clang/style-formatter/setup.sh
```
Installs `clang-format` from a vendored `.whl` file into a local Python venv.
No network access. No compiler. No admin rights required (installs in-repo).

**Method 3 -- clang-format + clang-tidy from vendored binaries (base case)**
```bash
bash scripts/setup-prebuilt-submodule.sh
bash toolchains/clang/source-build/setup.sh
```
Verifies and installs pre-built binaries from the `prebuilt-binaries`
submodule. Windows: instant. Linux: reassembles clang-tidy from split parts.

**Method 4 -- Build from LLVM source (worst case / policy requirement)**
```bash
bash toolchains/clang/source-build/setup.sh --build-from-source
```
Compiles `clang-format` and `clang-tidy` from the vendored LLVM 22.1.2
source tarball (~30-120 minutes). Use when pre-built binaries are not
permitted or Python is unavailable.
Requires: Visual Studio 2022 (Windows) or GCC 8+ (Linux). CMake 3.14+.

**Method 5 -- CMake 4.3.1**
```bash
bash build-tools/cmake/setup.sh
# or build from source:
bash build-tools/cmake/setup.sh --build-from-source
```
Installs CMake 4.3.1 to the devkit path. Required for RHEL 8 environments
where the system CMake is too old for modern C++ projects.

**Method 6 -- Portable Python 3.14.4**
```bash
bash languages/python/setup.sh
source languages/python/scripts/env-setup.sh
```
Installs a self-contained Python 3.14.4 alongside any existing system Python.
Does not affect system Python until `env-setup.sh` is sourced.
Also installs 10 vendored pip packages offline (numpy, pandas, plotly, streamlit,
requests, PyYAML, Jinja2, click, rich, pytest).

**Method 7 -- Portable .NET 10 SDK 10.0.201**
```bash
# Windows (Developer PowerShell):
cd languages\dotnet
.\install-prebuilt.ps1

# Linux:
bash languages/dotnet/setup.sh
```
Installs .NET 10 SDK 10.0.201 from prebuilt archives. No installer, no registry
changes, no elevation required for user install. Includes C# 14 compiler,
.NET Runtime, ASP.NET Core Runtime, MSBuild, NuGet client, and dotnet CLI.
Supported until November 2028.

**Method 8 -- VS Code extensions (offline)**
```bash
bash dev-tools/vscode-extensions/setup.sh
```
Installs C/C++, C++ TestMate, and Python extensions into VS Code offline.
Requires VS Code installed and `code` on PATH.

**Method 9 -- GCC toolchain for Windows**
```bash
cd toolchains/gcc/windows
bash setup.sh x86_64
source scripts/env-setup.sh x86_64
```
Installs GCC 15.2.0 + MinGW-w64 13.0.0 UCRT. Only needed if you require
GCC to compile C++ projects on Windows.

**Method 10 -- 7-Zip 26.00 (Windows + Linux)**
```bash
bash dev-tools/7zip/setup.sh
```
Installs 7-Zip 26.00. Admin mode: system-wide install. User mode: portable
drop-in with no elevation required.

**Method 11 -- Servy 7.8 (Windows service manager)**
```bash
bash dev-tools/servy/setup.sh
```
Installs Servy 7.8 portable. Turns any executable into a native Windows
service with health checks, log rotation, and restart policies.
Requires 7-Zip first. Windows only.

**Method 12 -- Conan 2.27.0 (C/C++ package manager)**
```bash
bash dev-tools/conan/setup.sh
```
Installs Conan 2.27.0 self-contained executable. No Python required.
Windows and Linux. Pairs with CMake for dependency management.

**Method 13 -- gRPC v1.78.1 for Windows (prebuilt)**
```powershell
cd frameworks\grpc
.\install-prebuilt.ps1 -version 1.78.1
.\setup.ps1 -version 1.78.1
```
Extracts prebuilt gRPC from `prebuilt-binaries/frameworks/grpc/windows/1.78.1/`
(69MB .7z -> 1.6GB install). No compiler or Visual Studio required for install.

**Method 14 -- gRPC v1.78.1 for Windows (source build)**
```powershell
cd frameworks\grpc
.\setup.ps1 -version 1.78.1
```
Builds gRPC from the vendored recursive source bundle (~40 minutes).
Requires: Visual Studio 2019/2022/Insiders with Desktop C++ workload,
CMake, Git Bash. All cmake deps sourced from `third_party/` -- no network access.

**Method 15 -- lcov code coverage (RHEL 8 / Linux)**
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
| Single entry point per tool | `bash install.sh` at root, or `bash setup.sh` per tool |
| Integrity verification | SHA256 pinned in `manifest.json` for all vendored archives and binaries |

---

## Repository Structure

```
airgap-cpp-devkit/
+-- README.md                              <- you are here
+-- TOOLS.md                               <- single-page tool inventory
+-- sbom.spdx.json                         <- root aggregate SBOM (SPDX 2.3)
+-- launch.sh                              <- PRIMARY entry point (devkit-ui or CLI fallback)
+-- install.sh                             <- CLI installer / fallback (no Python required)
+-- uninstall.sh                           <- removes all installed tools
+-- .gitmodules                            <- prebuilt-binaries submodule pointer
|
+-- scripts/
|   +-- install-mode.sh                    <- shared admin/user detection library
|   +-- setup-prebuilt-submodule.sh        <- initialize prebuilt-binaries submodule
|   +-- generate-sbom.sh                   <- regenerates all SBOM timestamps
|
+-- prebuilt-binaries/                     <- SUBMODULE (separate repo, optional)
|   +-- build-tools/cmake/                 <- CMake 4.3.1 (Windows .zip, Linux .tar.gz, source .tar.gz)
|   +-- dev-tools/7zip/                    <- 7-Zip 26.00
|   +-- dev-tools/servy/                   <- Servy 7.8 (single file ~80MB)
|   +-- dev-tools/conan/                   <- Conan 2.27.0 (Windows .zip, Linux .tgz)
|   +-- frameworks/grpc/windows/1.78.1/    <- gRPC prebuilt (.7z 69MB + .zip 162MB)
|   +-- languages/dotnet/10.0.201/         <- .NET 10 SDK (.7z 148MB + .zip 290MB, Linux .tar.gz 231MB)
|   +-- languages/python/                  <- Python 3.14.4 (Windows .zip, Linux .tar.gz 2 parts)
|   +-- toolchains/clang/mingw/            <- llvm-mingw 20260324
|   +-- toolchains/clang/rhel8/            <- Clang 20.1.8 RHEL8 RPMs
|   +-- toolchains/clang/source-build/     <- clang-format, clang-tidy, Ninja binaries
|   +-- toolchains/gcc/linux/              <- gcc-toolset-15 RHEL8 RPMs
|   +-- toolchains/gcc/windows/            <- WinLibs GCC 15.2.0
|
+-- build-tools/
|   +-- cmake/                             <- CMake 4.3.1 source + scripts
|   +-- lcov/                              <- lcov 2.4 + vendored Perl deps (Linux)
|
+-- dev-tools/
|   +-- 7zip/                              <- 7-Zip 26.00 scripts + manifests
|   +-- servy/                             <- Servy 7.8 scripts + manifests
|   +-- conan/                             <- Conan 2.27.0 scripts + manifests
|   +-- vscode-extensions/                 <- offline VS Code extensions
|   +-- devkit-ui/                         <- web-based package manager (FastAPI + HTMX)
|
+-- frameworks/
|   +-- grpc/                              <- gRPC v1.78.1 (Windows)
|
+-- languages/
|   +-- python/                            <- Python 3.14.4 (Windows + Linux) + pip packages
|   +-- dotnet/                            <- .NET 10 SDK 10.0.201 (Windows + Linux)
|
+-- toolchains/
    +-- clang/
    |   +-- source-build/                  <- clang-format + clang-tidy from LLVM source
    |   +-- style-formatter/               <- LLVM C++ style enforcement
    +-- gcc/
        +-- linux/                         <- gcc-toolset-15 for RHEL 8
        +-- windows/                       <- WinLibs GCC 15.2.0 for Windows
```