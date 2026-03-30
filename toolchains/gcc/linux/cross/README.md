# GCC 15.2 -- Linux Air-Gap Package

Prebuilt GCC 15.2 toolchain for Linux x86_64 (RHEL 8 / Rocky 8 compatible).

- **Source:** [tttapa/toolchains](https://github.com/tttapa/toolchains)
- **Includes:** gcc, g++, binutils, gdb, libstdc++
- **Host:** x86_64 Linux (glibc 2.17+, compatible with RHEL 8 / Rocky 8)
- **Target:** x86_64-linux-gnu (native compilation)

---

## Installation

```bash
# Verify, reassemble, and install
bash toolchains/gcc/linux/cross/setup.sh

# Verify SHA256 only -- no installation
bash toolchains/gcc/linux/cross/setup.sh --verify

# Show what would be installed without installing
bash toolchains/gcc/linux/cross/setup.sh --dry-run
```

Installs to:

| Mode | Path |
|------|------|
| Admin (root) | `/opt/airgap-cpp-devkit/toolchains/gcc/linux/cross/` |
| User | `~/.local/share/airgap-cpp-devkit/toolchains/gcc/linux/cross/` |

---

## Activation

```bash
source toolchains/gcc/linux/cross/scripts/env-setup.sh
gcc --version
g++ --version
```

This prepends the devkit GCC to PATH and sets `CC` and `CXX` environment
variables so CMake and other build tools pick it up automatically.

---

## Why This Toolchain?

RHEL 8 ships GCC 8.5, which does not support the C++17/C++20 features
required by modern C++ projects (gRPC, abseil, etc.). This toolchain provides
GCC 15.2 without modifying the system compiler.

The devkit GCC is opt-in -- it only activates when you source `env-setup.sh`.
Your system GCC 8.5 remains untouched.

---

## Vendored Files

| File | Size | Notes |
|------|------|-------|
| `x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz.part-aa` | 100MB | Split part 1 of 2 |
| `x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz.part-ab` | ~41MB | Split part 2 of 2 |

---

## Manual Reassembly

```bash
cat toolchains/gcc/linux/cross/vendor/x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz.part-{aa,ab} \
    > toolchains/gcc/linux/cross/vendor/x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz

sha256sum toolchains/gcc/linux/cross/vendor/x-tools-x86_64-bionic-linux-gnu-gcc15.tar.xz
# expected: 92cd7d00efa27298b6a2c7956afc6df4132051846c357547f278a52de56e7762
```

---

## Next Steps After Installing GCC 15.2

With GCC 15.2 active, you can build gRPC from source on RHEL 8:

```bash
source toolchains/gcc/linux/cross/scripts/env-setup.sh   # activate GCC 15.2
bash grpc-linux/setup.sh            # build gRPC (coming soon)
```