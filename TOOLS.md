# Tools Inventory

**Author: Nima Shafie**

Complete list of everything included in `airgap-cpp-devkit`.
All tools work without internet access. All dependencies are vendored.

> **Prebuilt available?** - If yes, no compiler or build tools required.
> Just extract and use. See each tool's README for details.

---

## Toolchains

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **clang-format** | 22.1.3 | Windows + Linux | Yes | `tools/toolchains/clang/source-build/` |
| **clang-tidy** | 22.1.3 | Windows + Linux | Yes | `tools/toolchains/clang/source-build/` |
| **LLVM source** | 22.1.3 | Windows + Linux | - (source only) | `tools/toolchains/clang/source-build/llvm-src/` |
| **llvm-mingw** | 20260324 | Windows + Linux | Yes | `prebuilt/toolchains/clang/mingw/` |
| **Clang RPMs** | 20.1.8 | RHEL 8 | Yes | `prebuilt/toolchains/clang/rhel8/` |
| **GCC + MinGW-w64** | 15.2.0 + 13.0.0 UCRT | Windows | Yes | `tools/toolchains/gcc/windows/` |
| **gcc-toolset** | 15 | RHEL 8 | Yes | `prebuilt/toolchains/gcc/linux/` |
| **GCC cross (x86_64-bionic)** | 15 | Linux | Yes | `tools/toolchains/gcc/linux/cross/` |
| **GCC native (RHEL 8)** | 15 | RHEL 8 | Yes | `tools/toolchains/gcc/linux/native/` |

---

## Build Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **CMake** | 4.3.1 | Windows + Linux | Yes | `tools/build-tools/cmake/` |
| **Ninja** | 1.13.2 | Windows + Linux | Yes | `prebuilt/toolchains/clang/source-build/` |
| **lcov** | 2.4 | Linux / RHEL 8 | Yes (vendored tarball) | `tools/build-tools/lcov/` |

---

## Frameworks

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **gRPC** | 1.80.0 | Windows | Yes (.zip, 4 parts) | `tools/frameworks/grpc/` |
| **gRPC source bundle** | 1.80.0 | Windows | - (source build ~40 min) | `tools/frameworks/grpc/vendor/` |

gRPC prebuilt includes: `bin/` (protoc, grpc_cpp_plugin, all plugins), `include/`, `lib/` (static), `share/` (cmake config).

---

## Languages

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **Python** | 3.14.4 | Windows (embeddable) | Yes (single file ~12 MB) | `tools/languages/python/` |
| **Python** | 3.14.4 | Linux x86_64 | Yes (tar.gz, 2 parts) | `tools/languages/python/` |
| **.NET SDK** | 10.0.201 | Windows x64 | Yes (.zip, 6 parts) | `tools/languages/dotnet/` |
| **.NET SDK** | 10.0.201 | Linux x64 | Yes (.tar.gz, 6 parts) | `tools/languages/dotnet/` |

---

## Developer Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **7-Zip** | 26.00 | Windows + Linux | Yes | `tools/dev-tools/7zip/` |
| **FileZilla** | 3.70.4 | Windows + Linux | Yes | `tools/dev-tools/filezilla/` |
| **GDB** | 17.1 | Linux | No (source build ~25 min) | `tools/dev-tools/gdb/` |
| **Notepad++** | 8.9.3 | Windows | Yes (portable zip + installer) | `tools/dev-tools/notepadpp/` |
| **PuTTY** | 0.83 | Windows + Linux | Yes (Win MSI) / source build (Linux) | `tools/dev-tools/putty/` |
| **SourceTree** | 3.4.30 | Windows | Yes | `tools/dev-tools/sourcetree/` |
| **Servy** | 7.9 | Windows | Yes (single file ~80 MB) | `tools/dev-tools/servy/` |
| **Conan** | 2.27.1 | Windows + Linux | Yes (self-contained) | `tools/dev-tools/conan/` |
| **VS Code extensions** | Various | Windows + Linux | Yes (.vsix) | `tools/dev-tools/vscode-extensions/` |
| **SQLite CLI** | 3.53.0 (Win) / 3.26.0 RPM (RHEL 8) | Windows + Linux | Yes | `tools/dev-tools/sqlite/` |
| **MATLAB verification** | - | Windows + Linux | - (checks existing install) | `tools/dev-tools/matlab/` |
| **git-bundle transfer tool** | - | Windows + Linux | - (Python scripts) | `tools/dev-tools/git-bundle/` |
| **devkit-ui** | - | Windows + Linux | - (Python web app) | `tools/dev-tools/devkit-ui/` |
| **LLVM style formatter** | 22.1.3 | Windows + Linux | Yes (via pip wheel) | `tools/toolchains/clang/style-formatter/` |

---

## DevKit UI Notes

`tools/dev-tools/devkit-ui/` is the **preferred** way to install and manage devkit tools.
The root-level `launch.sh` script finds Python automatically and starts it — no manual
setup required. On first run it bootstraps its own Python dependencies (FastAPI,
uvicorn, jinja2, aiofiles) then opens `http://127.0.0.1:8080` in your browser.

**Entry point:** `bash launch.sh` (not `python devkit.py` directly).

**Features:** dashboard grid showing installed/not-installed status per tool, one-click
Install / Rebuild, profile-based batch installs (cpp-dev / devops / minimal / full),
and an inline log browser.

**Fallback:** if Python 3.8+ is not on PATH, `launch.sh` automatically falls back to
`install-cli.sh`. Force the fallback at any time with `bash launch.sh --cli`.

**Air-gap:** pre-download wheels to `tools/dev-tools/devkit-ui/vendor/` and the launcher
uses them instead of PyPI. All other devkit tools remain fully CLI-installable via
`install-cli.sh` regardless of whether devkit-ui is used.

---

## VS Code Extensions

| Extension | Version | Platform |
|-----------|---------|----------|
| ms-vscode.cpptools-extension-pack | 1.5.1 | Any |
| ms-vscode.cpptools | 1.30.4 | win32-x64 + linux-x64 |
| matepek.vscode-catch2-test-adapter | 4.22.3 | Any |
| ms-python.python | 2026.5.x | win32-x64 + linux-x64 |

---

## Python Pip Packages

All packages are vendored as `.whl` files in `tools/languages/python/pip-packages/`
and installed offline by `tools/languages/python/setup.sh`. No internet access required.
Platform-specific wheels are provided for both Windows (win_amd64) and Linux (manylinux).

### Core packages

| Package | Version | License | Purpose |
|---------|---------|---------|---------|
| **numpy** | 2.4.4 | BSD-3-Clause | Numerical computing -- arrays, linear algebra, FFT |
| **pandas** | 3.0.2 | BSD-3-Clause | Data analysis -- DataFrames, CSV/Excel/SQL I/O |
| **scipy** | 1.17.1 (Win) / 1.16.3 (Linux) | BSD-3-Clause | Scientific computing -- stats, signal processing |
| **scikit-learn** | 1.8.0 | BSD-3-Clause | Machine learning |
| **matplotlib** | 3.10.8 | PSF | Plotting -- charts, figures |
| **plotly** | 6.7.0 | MIT | Interactive visualizations -- charts, dashboards |
| **pillow** | 12.2.0 | HPND | Image processing |
| **streamlit** | 1.56.0 | Apache-2.0 | Data app framework -- web UIs in pure Python |
| **sqlalchemy** | 2.0.49 | MIT | Database ORM -- SQL abstraction layer |
| **requests** | 2.33.1 | Apache-2.0 | HTTP client -- REST APIs, file downloads |
| **PyYAML** | 6.0.3 | MIT | YAML parsing -- config files, CI definitions |
| **pydantic** | 2.12.5 | MIT | Data validation -- type-safe models |
| **openpyxl** | 3.1.5 | MIT | Excel I/O -- read/write .xlsx files |
| **Jinja2** | 3.1.6 | BSD-3-Clause | Templating -- used by Conan, CMake, code gen tools |
| **python-dotenv** | 1.2.2 | BSD-3-Clause | .env file loading |
| **click** | 8.3.2 | BSD-3-Clause | CLI framework -- write devkit helper scripts |
| **rich** | 14.3.3 | MIT | Terminal output -- colored tables, progress bars |
| **loguru** | 0.7.3 | MIT | Logging -- drop-in replacement for stdlib logging |
| **win32-setctime** | 1.2.0 | MIT | Windows file creation time (loguru dep, Windows only) |
| **pytest** | 9.0.3 | MIT | Test runner -- for Python scripts in the devkit |
| **certifi** | 2026.2.25 | MPL-2.0 | Mozilla CA bundle -- TLS certificate verification |
| **charset-normalizer** | 3.4.7 | MIT | Character encoding detection (requests dependency) |
| **colorama** | 0.4.6 | BSD-3-Clause | Cross-platform ANSI color codes in the terminal |
| **idna** | 3.10 | BSD-3-Clause | Internationalized domain name support (requests dependency) |
| **urllib3** | 2.4.0 | MIT | HTTP connection pooling (requests dependency) |
| **PySimpleSOAP** | 1.16.2 | LGPL-2.1 | Lightweight SOAP client and server |
| **pywin32** | 308 | PSF | Python bindings for Windows APIs (Windows only) |

### Transitive dependencies (auto-installed)

altair, annotated-types, attrs, blinker, cachetools, contourpy, cycler,
et-xmlfile, fonttools, gitdb, gitpython, greenlet, iniconfig, joblib, jsonschema,
jsonschema-specifications, kiwisolver, markdown-it-py, markupsafe, mdurl, narwhals,
packaging, pluggy, protobuf, pyarrow, pydantic-core, pydeck, pygments, pyparsing,
python-dateutil, referencing, rpds-py, six, smmap, tenacity, threadpoolctl, toml,
tornado, typing-extensions, typing-inspection, tzdata, watchdog

---

## SQLite Notes

On **Windows** and modern Linux: prebuilt CLI binary from sqlite.org (version 3.53.0).
On **RHEL 8**: system RPM (sqlite-3.26.0) installed via `rpm -i` — the sqlite.org
prebuilt requires GLIBC 2.29+ which RHEL 8 does not provide (ships GLIBC 2.28).

---

## MATLAB Notes

`tools/dev-tools/matlab/` provides **verification only** — it checks that MATLAB is
installed and that required toolboxes (Database Toolbox, MATLAB Compiler) are
licensed. It does not install MATLAB. If MATLAB is not installed the script exits
cleanly with a skip message.

---

## Prebuilt Binary Formats

Files above 49MB are split into parts for compatibility with GitHub and Bitbucket.
Files under 49MB are stored as single files.
All .zip archives use deflate level 9 compression.

| Archive | Size | Parts | Split at |
|---------|------|-------|----------|
| gRPC 1.80.0 Windows (.zip) | 170MB | 4 | 49MB |
| WinLibs GCC 15.2.0 Windows (.zip) | 264MB | 6 | 49MB |
| llvm-mingw 20260324 Windows (.zip) | 179MB | 4 | 49MB |
| llvm-mingw 20260324 Linux (.tar.xz) | 82MB | 2 | 50MB |
| .NET SDK 10.0.201 Windows (.zip) | 283MB | 6 | 49MB |
| .NET SDK 10.0.201 Linux (.tar.gz) | 231MB | 6 | 45MB |
| Python 3.14.4 Linux (.tar.gz) | 120MB | 2 | 99MB |
| Clang LLVM 22.1.3 Linux slim (.tar.xz) | 124MB | 3 | 50MB |
| clang-tidy Linux | 95MB | 2 | 50MB |
| Clang 20.1.8 RHEL8 RPMs (.tar) | 101MB | 2 | 50MB |
| gcc-toolset-15 RHEL8 RPMs (.tar) | 87MB | 2 | 50MB |
| CMake 4.3.1 Linux (.tar.gz) | 61MB | 1 | -- single file |
| CMake 4.3.1 Windows (.zip) | 51MB | 1 | -- single file |
| Servy 7.9 Windows (.7z) | 80MB | 1 | -- single file |
| Conan 2.27.1 Windows (.zip) | 15MB | 1 | -- single file |
| Conan 2.27.1 Linux (.tgz) | 27MB | 1 | -- single file |
| Python 3.14.4 Windows embed (.zip) | 12MB | 1 | -- single file |
| SQLite 3.53.0 Windows CLI (.zip) | 6.2MB | 1 | -- single file |
| SQLite 3.53.0 Linux CLI (.zip) | 4.1MB | 1 | -- single file |
| SQLite 3.26.0 RHEL 8 (.rpm) | 668KB | 1 | -- single file |
| 7-Zip 26.00 Windows installer (.exe) | 1.6MB | 1 | -- single file |
| 7-Zip 26.00 Windows extra (.7z) | 1.6MB | 1 | -- single file |
| 7-Zip 26.00 Linux (.tar.xz) | 1.5MB | 1 | -- single file |

---

## Platform Support Matrix

| Tool | Windows 11 | RHEL 8 | Notes |
|------|-----------|--------|-------|
| clang-format / clang-tidy | Yes | Yes | Prebuilt for both |
| llvm-mingw | Yes | Yes | Cross-compile toolchain |
| GCC + MinGW-w64 | Yes | - | Windows native toolchain |
| gcc-toolset 15 | - | Yes | RHEL 8 RPMs |
| GCC cross/native | - | Yes | Linux only |
| CMake 4.3.1 | Yes | Yes | Prebuilt for both |
| Ninja | Yes | Yes | Prebuilt for both |
| gRPC 1.80.0 | Yes | - | Windows MSVC build only |
| Python 3.14.4 | Yes | Yes | Different packages per platform |
| .NET SDK 10.0.201 | Yes | Yes | Portable, no installer |
| 7-Zip 26.00 | Yes | Yes | Admin + user install |
| FileZilla 3.70.4 | Yes | Yes | Prebuilt installer (Win) + binary tarball (Linux) |
| GDB 17.1 | - | Yes | Linux source build; requires gcc, make, readline-devel |
| Notepad++ 8.9.3 | Yes | - | Windows only; portable zip (no admin) + installer available |
| PuTTY 0.83 | Yes (MSI) | Yes (source) | Linux builds CLI tools only; requires cmake + gcc |
| SourceTree 3.4.30 | Yes | - | Windows only; Squirrel installer targets %LocalAppData%\SourceTree |
| Servy 7.9 | Yes | - | Windows only, graceful no-op on Linux |
| Conan 2.27.1 | Yes | Yes | Self-contained, no Python required |
| VS Code extensions | Yes | Yes | Per-platform .vsix files |
| SQLite CLI | Yes (3.53.0) | Yes (3.26.0 RPM) | RHEL 8 uses system RPM |
| MATLAB verification | Yes | Yes | Checks existing install only |
| git-bundle tool | Yes | Yes | Pure Python, no deps |
| LLVM style formatter | Yes | Yes | Git pre-commit hook |
| devkit-ui | Yes | Yes | Python 3.8+, auto-installs FastAPI + uvicorn |
| lcov 2.4 | - | Yes | Linux/RHEL 8 only |

---

## Install Profiles

Use `--profile <name>` with `install-cli.sh` to pre-select tools without prompts:

| Profile | Tools selected |
|---------|---------------|
| `cpp-dev` | conan, vscode-extensions, sqlite, 7zip |
| `devops` | conan, sqlite, 7zip |
| `minimal` | required tools only (clang, cmake, python, style-formatter) |
| `full` | all optional tools |

```bash
# Non-interactive install for C++ developers
bash install-cli.sh --yes --profile cpp-dev

# Non-interactive minimal install
bash install-cli.sh --yes --profile minimal
```

---

## Quick Install Reference

```bash
# PREFERRED: launch the DevKit Manager web UI
bash launch.sh                                  # opens http://127.0.0.1:8080
bash launch.sh --port 9090                      # custom port
bash launch.sh --host 0.0.0.0                   # LAN / remote access
bash launch.sh --no-browser                     # server only
bash launch.sh --cli                            # force CLI installer (install-cli.sh)

# CLI fallback (no Python required)
bash install-cli.sh                                 # full interactive wizard
bash install-cli.sh --yes --profile cpp-dev         # non-interactive with profile

# Individual tool installs (also available from the web UI)
bash tools/toolchains/clang/source-build/setup.sh    # clang-format + clang-tidy
bash tools/toolchains/clang/style-formatter/bootstrap.sh  # pre-commit hook
bash tools/build-tools/cmake/setup.sh                # CMake 4.3.1
bash tools/build-tools/lcov/setup.sh                 # lcov 2.4 (Linux only)
bash tools/languages/python/setup.sh                 # Python 3.14.4 + pip packages
bash tools/dev-tools/conan/setup.sh                  # Conan 2.27.1
bash tools/dev-tools/7zip/setup.sh                   # 7-Zip 26.00
bash tools/dev-tools/servy/setup.sh                  # Servy 7.9 (Windows only)
bash tools/dev-tools/sqlite/setup.sh                 # SQLite CLI
bash tools/dev-tools/matlab/setup.sh                 # MATLAB verification
bash tools/dev-tools/vscode-extensions/setup.sh      # VS Code extensions
bash tools/toolchains/gcc/windows/setup.sh x86_64    # GCC + MinGW-w64 (Windows only)
```

---

## Binary Policy

The **main repo contains no compiled binaries** (no `.exe`, `.dll`, `.msi`, or
pre-compiled object files). All binaries live exclusively in the
`prebuilt/` submodule, which can be skipped entirely in
binary-restricted environments.

Everything in the main repo is source code, shell scripts, PowerShell scripts,
vendored source archives (`.tar.gz`, `.tar.xz`), and split archive parts of
those source archives.