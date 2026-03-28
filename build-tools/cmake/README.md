# cmake

### Author: Nima Shafie

Installs **CMake 4.3.0** from vendored prebuilt binaries (default, seconds),
or builds from the vendored source tarball (`--build-from-source`, ~10-20 min).

---

## Usage

```bash
bash cmake/bootstrap.sh                    # prebuilt (default)
bash cmake/bootstrap.sh --build-from-source
bash cmake/bootstrap.sh --rebuild          # force re-install
```

---

## When to Use Each Path

| Scenario | Recommended |
|----------|-------------|
| Air-gapped, binaries permitted | `bootstrap.sh` (prebuilt, default) |
| Binary-restricted environment | `bootstrap.sh --build-from-source` |
| Force reinstall / version change | `bootstrap.sh --rebuild` |

---

## What It Does

### Prebuilt path (default)

**Linux:**
1. Verifies `cmake-4.3.0-linux-x86_64.tar.gz.part-aa/ab` SHA256 against `manifest.json`
2. Reassembles the split archive
3. Extracts and installs to the install directory

**Windows:**
1. Verifies `cmake-4.3.0-windows-x86_64.zip.part-aa/ab` SHA256 against `manifest.json`
2. Reassembles the split archive
3. Extracts and installs to the install directory

### Source build path (`--build-from-source`)

Both platforms:
1. Verifies `cmake-4.3.0.tar.gz` SHA256 against `manifest.json`
2. Extracts vendored source
3. Runs CMake's own `bootstrap` script
4. Builds with `make -j$(nproc)`
5. Installs to the install directory

**Build prerequisites (`--build-from-source` only):**

| Platform | Requirement |
|----------|-------------|
| Linux (RHEL 8) | GCC 8.5+ (`sudo dnf install gcc-c++`) |
| Windows | WinLibs GCC on PATH (`winlibs-gcc-ucrt/bootstrap.sh` first) |

---

## Install Locations

| Mode | Linux | Windows |
|------|-------|---------|
| Admin | `/opt/airgap-cpp-devkit/cmake/` | `C:\Program Files\airgap-cpp-devkit\cmake\` |
| User | `~/.local/share/airgap-cpp-devkit/cmake/` | `%LOCALAPPDATA%\airgap-cpp-devkit\cmake\` |

After install, add to PATH:
```bash
# Linux
export PATH="/opt/airgap-cpp-devkit/cmake/bin:$PATH"

# Windows (Git Bash)
export PATH="/c/Program Files/airgap-cpp-devkit/cmake/bin:$PATH"
```

---

## Vendored Files (in `prebuilt-binaries/build-tools/cmake/`)

| File | Purpose | Size |
|------|---------|------|
| `cmake-4.3.0-linux-x86_64.tar.gz.part-aa` | Linux prebuilt part 1 | ~50 MB |
| `cmake-4.3.0-linux-x86_64.tar.gz.part-ab` | Linux prebuilt part 2 | ~12 MB |
| `cmake-4.3.0-windows-x86_64.zip.part-aa` | Windows prebuilt part 1 | ~50 MB |
| `cmake-4.3.0-windows-x86_64.zip.part-ab` | Windows prebuilt part 2 | ~464 KB |
| `cmake-4.3.0.tar.gz` | Source tarball (both platforms) | ~13 MB |

All SHA256s are pinned in `cmake/manifest.json`.

---

## Updating to a New CMake Version (Maintainers Only)

On a machine with internet access, download from https://cmake.org/download/:

```bash
cd prebuilt-binaries/build-tools/cmake/

# Download
curl -LO https://github.com/Kitware/CMake/releases/download/v4.x.x/cmake-4.x.x-linux-x86_64.tar.gz
curl -LO https://github.com/Kitware/CMake/releases/download/v4.x.x/cmake-4.x.x-windows-x86_64.zip
curl -LO https://github.com/Kitware/CMake/releases/download/v4.x.x/cmake-4.x.x.tar.gz

# Split oversized files
split -b 52428800 cmake-4.x.x-linux-x86_64.tar.gz cmake-4.x.x-linux-x86_64.tar.gz.part-
split -b 52428800 cmake-4.x.x-windows-x86_64.zip  cmake-4.x.x-windows-x86_64.zip.part-
rm cmake-4.x.x-linux-x86_64.tar.gz cmake-4.x.x-windows-x86_64.zip

# SHA256
sha256sum cmake-4.x.x-linux-x86_64.tar.gz.part-*
sha256sum cmake-4.x.x-windows-x86_64.zip.part-*
sha256sum cmake-4.x.x.tar.gz

# Update cmake/manifest.json with new version + hashes
# Update CMAKE_VERSION in cmake/bootstrap.sh
# Update version references in this README

git add .
git commit -m "vendor: update CMake to 4.x.x"
git push
```