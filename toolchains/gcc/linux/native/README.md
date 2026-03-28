# toolchains/gcc/linux/native

Vendors Red Hat `toolchains/gcc/linux/native-15` RPMs for air-gapped RHEL 8 / Rocky Linux 8
deployment. Provides GCC 15.1.1, G++ 15.1.1, and critically a modern
`libstdc++` with `GLIBCXX_3.4.30+` — which fixes runtime errors from binaries
built with LLVM 22.x.

**Linux only — no Windows component.**

## What's Included

| Package | Version | Purpose |
|---------|---------|---------|
| `toolchains/gcc/linux/native-15-gcc` | 15.1.1 | GCC C compiler |
| `toolchains/gcc/linux/native-15-gcc-c++` | 15.1.1 | G++ C++ compiler |
| `toolchains/gcc/linux/native-15-runtime` | 15.0 | SCL runtime wrapper |
| `toolchains/gcc/linux/native-15-libstdc++-devel` | 15.1.1 | libstdc++ with GLIBCXX_3.4.30+ |
| `toolchains/gcc/linux/native-15-binutils` | 2.44 | GNU linker, assembler |
| `scl-utils` | 2.0.2 | Software Collections framework |
| `environment-modules` | 4.5.2 | Module environment support |

## Vendored Assets

All RPMs are in `prebuilt-binaries/toolchains/gcc/linux/native/`:

```
toolchains/gcc/linux/native-15-rhel8-rpms.tar.part-aa  (50 MB)
toolchains/gcc/linux/native-15-rhel8-rpms.tar.part-ab  (34 MB)
```

## Usage

```bash
# Install (requires root)
bash toolchains/gcc/linux/native/setup.sh

# Activate in current shell
source /opt/rh/toolchains/gcc/linux/native-15/enable

# Verify
gcc --version    # should show 15.1.1
g++ --version    # should show 15.1.1
```

## Install Path

toolchains/gcc/linux/native always installs to `/opt/rh/toolchains/gcc/linux/native-15/` — this is the
standard SCL path and cannot be changed.

## libstdc++ for clang-format / clang-tidy

After installing toolchains/gcc/linux/native-15, use its libstdc++ to run the devkit's
clang-format and clang-tidy binaries:

```bash
# Find the libstdc++ path
LIBDIR="$(find /opt/rh/toolchains/gcc/linux/native-15 -name 'libstdc++.so*' -exec dirname {} \; | head -1)"
export LD_LIBRARY_PATH="${LIBDIR}:${LD_LIBRARY_PATH:-}"

# Now clang-format and clang-tidy work
/opt/airgap-cpp-devkit/toolchains/clang/clang-format-linux --version
/opt/airgap-cpp-devkit/toolchains/clang/clang-tidy-linux --version
```

Or add to `~/.bashrc`:
```bash
source /opt/rh/toolchains/gcc/linux/native-15/enable
```

## Prerequisites

- RHEL 8 or Rocky Linux 8 (x86_64)
- Root / sudo access for `rpm -Uvh`

## Upstream

- GCC: https://gcc.gnu.org/ (GPL-3.0)
- RPM source: Rocky Linux 8.10 AppStream
  (`https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/`)