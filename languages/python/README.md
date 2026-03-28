# Python 3.14.3 — Air-Gap Package

Portable Python 3.14.3 interpreter for air-gapped Windows and Linux (RHEL 8 / x86-64) systems.

- **Linux:** python-build-standalone (astral-sh) — self-contained, no system dependencies
- **Windows:** Official Python.org embeddable package — no installer, no admin rights required

---

## Installation

```bash
# Verify, reassemble (Linux), and install
bash python/bootstrap.sh

# Verify SHA256 only — no installation
bash python/bootstrap.sh --verify

# Show what would be installed without installing
bash python/bootstrap.sh --dry-run
```

Installs to:

| Mode | Linux | Windows |
|------|-------|---------|
| Admin (root) | `/opt/airgap-cpp-devkit/python/` | `C:\Program Files\airgap-cpp-devkit\python\` |
| User | `~/.local/share/airgap-cpp-devkit/python/` | `%LOCALAPPDATA%\airgap-cpp-devkit\python\` |

---

## Activation

```bash
source python/scripts/env-setup.sh
python3.14 --version
```

---

## Vendored Files

| File | Platform | Size | Notes |
|------|----------|------|-------|
| `cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz.part-aa` | Linux | 100MB | Split part 1 of 2 |
| `cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz.part-ab` | Linux | ~19MB | Split part 2 of 2 |
| `python-3.14.3-embed-amd64.zip` | Windows | ~12MB | Single file |

The Linux tarball is split due to git file size limits. `bootstrap.sh` reassembles it automatically.

---

## Manual Reassembly (Linux)

```bash
cat python/vendor/cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz.part-{aa,ab} \
    > python/vendor/cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz

sha256sum python/vendor/cpython-3.14.3+20260203-x86_64-unknown-linux-gnu-install_only.tar.gz
# expected: d4c6712210b69540ab4ed51825b99388b200e4f90ca4e53fbb5a67c2467feb48
```

---

## Updating

To update to a newer Python version:

1. Download new packages from:
   - Linux: `https://github.com/astral-sh/python-build-standalone/releases`
   - Windows: `https://www.python.org/downloads/`
2. Split the Linux tarball: `split -b 100m <tarball> <tarball>.part-`
3. Compute SHA256 for all files and parts
4. Replace files in `vendor/`
5. Update `manifest.json` and `sbom.spdx.json`
6. Run `bash python/bootstrap.sh --verify`