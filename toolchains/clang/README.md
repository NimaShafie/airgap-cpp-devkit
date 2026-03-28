# toolchains/clang

Vendors LLVM/Clang toolchain components for air-gapped environments.
Supports Windows 11 and RHEL 8, admin and user install modes.

## Components

### clang-linux (Linux only)
Slim Clang/LLVM 22.1.2 toolchain for Linux x86_64. Cherry-picked from the
official LLVM 22.1.2 release — contains only the binaries needed for C/C++
compilation and toolchain use.

| Binary | Purpose |
|--------|---------|
| `clang` / `clang++` | C/C++ compiler (symlinks to `clang-22`) |
| `lld` / `ld.lld` | LLVM linker |
| `llvm-ar` | Archive tool (also `llvm-ranlib` symlink) |
| `llvm-nm` | Symbol table lister |
| `llvm-objcopy` / `llvm-strip` | Object file manipulation |
| `llvm-objdump` | Object file disassembler |
| `llvm-config` | LLVM build system helper |
| `llvm-symbolizer` | Symbol resolution (used by sanitizers) |

### llvm-mingw (both platforms)
llvm-mingw 20260324 (LLVM 22.1.2) — LLVM/Clang/LLD based mingw-w64 toolchain.

- **Linux**: Cross-compiler running on Linux x86_64, targeting all four Windows
  architectures (i686, x86_64, armv7, arm64). UCRT runtime.
- **Windows**: Native toolchain running on Windows x86_64, targeting all four
  Windows architectures. UCRT runtime.

## Vendored Assets

All binaries are in `prebuilt-binaries/toolchains/clang/`:

```
clang-linux/
  toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-aa  (50 MB)
  toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ab  (50 MB)
  toolchains/clang-22.1.2-linux-x64-slim.tar.xz.part-ac  (19 MB)

llvm-mingw/
  llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-aa  (50 MB)  ← Linux
  llvm-mingw-20260324-ucrt-ubuntu-22.04-x86_64.tar.xz.part-ab  (29 MB)  ← Linux
  llvm-mingw-20260324-ucrt-x86_64.zip.part-aa  (50 MB)  ← Windows
  llvm-mingw-20260324-ucrt-x86_64.zip.part-ab  (50 MB)  ← Windows
  llvm-mingw-20260324-ucrt-x86_64.zip.part-ac  (50 MB)  ← Windows
  llvm-mingw-20260324-ucrt-x86_64.zip.part-ad  (29 MB)  ← Windows
```

## Usage

```bash
# Install everything (auto-detects platform and install mode)
bash toolchains/clang/setup.sh

# Install only clang (Linux only)
bash toolchains/clang/setup.sh --component clang

# Install only llvm-mingw
bash toolchains/clang/setup.sh --component mingw

# Custom prefix
bash toolchains/clang/setup.sh --prefix /opt/tools/llvm
```

## Install Paths

| Mode | Platform | clang | llvm-mingw |
|------|----------|-------|------------|
| Admin | Linux | `/opt/airgap-cpp-devkit/toolchains/clang/clang/` | `/opt/airgap-cpp-devkit/toolchains/clang/llvm-mingw/` |
| User | Linux | `~/.local/share/airgap-cpp-devkit/toolchains/clang/clang/` | `~/.local/share/.../llvm-mingw/` |
| Admin | Windows | `C:\Program Files\airgap-cpp-devkit\toolchains/clang\llvm-mingw\` | same |
| User | Windows | `%LOCALAPPDATA%\airgap-cpp-devkit\toolchains/clang\llvm-mingw\` | same |

## Cross-Compilation with llvm-mingw (Linux → Windows)

After install, cross-compile for Windows from Linux:

```bash
# Compile for Windows x86_64
x86_64-w64-mingw32-clang -o myapp.exe myapp.c

# Compile for Windows arm64
aarch64-w64-mingw32-clang -o myapp.exe myapp.c

# C++
x86_64-w64-mingw32-clang++ -o myapp.exe myapp.cpp
```

## Prerequisites

- **7-Zip** required for Windows llvm-mingw extraction. Install first:
  `bash dev-tools/7zip/setup.sh`
- **GCC 15.2** (`toolchains/gcc/linux/cross` module) recommended on Linux for libstdc++ runtime
  compatibility when using clang with GCC's standard library.

## Upstream

- LLVM/Clang: https://github.com/llvm/llvm-project (Apache-2.0 WITH LLVM-exception)
- llvm-mingw: https://github.com/mstorsjo/llvm-mingw (MIT + component licenses)