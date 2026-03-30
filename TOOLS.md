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
| **clang-format** | 22.1.2 | Windows + Linux | Yes Yes | `toolchains/clang/source-build/` |
| **clang-tidy** | 22.1.2 | Windows + Linux | Yes Yes | `toolchains/clang/source-build/` |
| **LLVM source** | 22.1.2 | Windows + Linux | - (source only) | `toolchains/clang/source-build/llvm-src/` |
| **llvm-mingw** | 20260324 | Windows + Linux | Yes Yes | `prebuilt-binaries/toolchains/clang/mingw/` |
| **Clang RPMs** | 20.1.8 | RHEL 8 | Yes Yes | `prebuilt-binaries/toolchains/clang/rhel8/` |
| **GCC + MinGW-w64** | 15.2.0 + 13.0.0 UCRT | Windows | Yes Yes | `toolchains/gcc/windows/` |
| **gcc-toolset** | 15 | RHEL 8 | Yes Yes | `prebuilt-binaries/toolchains/gcc/linux/` |
| **GCC cross (x86_64-bionic)** | 15 | Linux | Yes Yes | `toolchains/gcc/linux/cross/` |
| **GCC native (RHEL 8)** | 15 | RHEL 8 | Yes Yes | `toolchains/gcc/linux/native/` |

---

## Build Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **CMake** | 4.3.0 | Windows + Linux | Yes Yes | `build-tools/cmake/` |
| **Ninja** | 1.13.2 | Windows + Linux | Yes Yes | `prebuilt-binaries/toolchains/clang/source-build/` |
| **lcov** | 2.4 | Linux / RHEL 8 | Yes Yes (vendored tarball) | `build-tools/lcov/` |

---

## Frameworks

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **gRPC** | 1.78.1 | Windows | Yes Yes (.7z 69MB) | `frameworks/grpc/` |
| **gRPC source bundle** | 1.78.1 | Windows | - (source build ~40 min) | `frameworks/grpc/vendor/` |

gRPC prebuilt includes: `bin/` (protoc, grpc_cpp_plugin, all plugins), `include/`, `lib/` (static), `share/` (cmake config).

---

## Languages

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **Python** | 3.14.3 | Windows (embeddable) | Yes Yes (.7z 8.9MB) | `languages/python/` |
| **Python** | 3.14.3 | Linux x86_64 | Yes Yes (tar.gz, 3 parts) | `languages/python/` |
| **.NET SDK** | 10.0.201 | Windows x64 | Yes (.7z 148MB) | `languages/dotnet/` |
| **.NET SDK** | 10.0.201 | Linux x64 | Yes (.tar.gz 231MB) | `languages/dotnet/` |

---

## Developer Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **7-Zip** | 26.00 | Windows + Linux | Yes Yes | `dev-tools/7zip/` |
| **Servy** | 7.3 | Windows | Yes Yes (.7z, 2 parts) | `dev-tools/servy/` |
| **VS Code extensions** | Various | Windows + Linux | Yes Yes (.vsix) | `dev-tools/vscode-extensions/` |
| **git-bundle transfer tool** | - | Windows + Linux | - (Python scripts) | `dev-tools/git-bundle/` |
| **LLVM style formatter** | 22.1.2 | Windows + Linux | Yes Yes (via pip wheel) | `toolchains/clang/style-formatter/` |

---

## VS Code Extensions

| Extension | Version | Platform |
|-----------|---------|----------|
| ms-vscode.cpptools-extension-pack | 1.5.1 | Any |
| ms-vscode.cpptools | 1.30.4 | win32-x64 + linux-x64 |
| matepek.vscode-catch2-test-adapter | 4.22.3 | Any |
| ms-python.python | 2026.5.x | win32-x64 + linux-x64 |

---

## Prebuilt Binary Formats

All large archives are split into `<=50MB` parts for git compatibility.
Both `.zip` and `.7z` (ultra compression) are provided where applicable.
Install scripts auto-select `.7z` when 7-Zip is available.

| Archive | .zip size | .7z size | Savings |
|---------|-----------|----------|---------|
| gRPC 1.78.1 Windows x64 | 162MB | 69MB | 57% |
| WinLibs GCC 15.2.0 | 254MB | 102MB | 60% |
| llvm-mingw 20260324 Windows | 178MB | 74MB | 58% |
| CMake 4.3.0 Windows | 51MB | 20MB | 61% |
| Python 3.14.3 Windows embed | 14MB | 9MB | 36% |

---

## Platform Support Matrix

| Tool | Windows 11 | RHEL 8 | Notes |
|------|-----------|--------|-------|
| clang-format / clang-tidy | Yes | Yes | Prebuilt for both |
| llvm-mingw | Yes | Yes | Cross-compile toolchain |
| GCC + MinGW-w64 | Yes | - | Windows native toolchain |
| gcc-toolset 15 | - | Yes | RHEL 8 RPMs |
| GCC cross/native | - | Yes | Linux only |
| CMake 4.3.0 | Yes | Yes | Prebuilt for both |
| Ninja | Yes | Yes | Prebuilt for both |
| gRPC 1.78.1 | Yes | - | Windows MSVC build only |
| Python 3.14.3 | Yes | Yes | Different packages per platform |
| 7-Zip 26.00 | Yes | Yes | Admin + user install |
| Servy 7.3 | Yes | - | Windows only, graceful no-op on Linux |
| VS Code extensions | Yes | Yes | Per-platform .vsix files |
| git-bundle tool | Yes | Yes | Pure Python, no deps |
| LLVM style formatter | Yes | Yes | Git pre-commit hook |
| lcov 2.4 | - | Yes | Linux/RHEL 8 only |

---

## Quick Install Reference

```bash
# Formatter + style enforcement (fastest, ~5 seconds)
bash toolchains/clang/style-formatter/setup.sh

# clang-format + clang-tidy prebuilt
bash toolchains/clang/source-build/setup.sh

# CMake 4.3.0
bash build-tools/cmake/setup.sh

# Python 3.14.3
bash languages/python/setup.sh

# GCC 15.2.0 for Windows
bash toolchains/gcc/windows/setup.sh

# 7-Zip 26.00
bash dev-tools/7zip/setup.sh

# Servy 7.3 (Windows only)
bash dev-tools/servy/setup.sh

# gRPC 1.78.1 - prebuilt (Developer PowerShell)
cd frameworks\grpc && .\install-prebuilt.ps1 -version 1.78.1

# gRPC 1.78.1 - source build (~40 min, Developer PowerShell)
cd frameworks\grpc && .\setup.ps1 -version 1.78.1

# lcov 2.4 (Linux/RHEL 8 only)
bash build-tools/lcov/setup.sh
```

---

## Binary Policy

The **main repo contains no compiled binaries** (no `.exe`, `.dll`, `.msi`, or
pre-compiled object files). All binaries live exclusively in the
`prebuilt-binaries/` submodule, which can be skipped entirely in
binary-restricted environments.

Everything in the main repo is source code, shell scripts, PowerShell scripts,
vendored source archives (`.tar.gz`, `.tar.xz`), and split archive parts of
those source archives.