# 7-Zip 26.00 -- Prebuilt Module

Vendors 7-Zip 26.00 for air-gapped environments. Supports both **admin** (system-wide)
and **user** (no-root/no-elevation) install modes on Windows 11 and RHEL 8.

## Vendored Assets

Binaries are stored in the `prebuilt-binaries/7zip/` submodule:

| File | Platform | Purpose |
|------|----------|---------|
| `prebuilt-binaries/7zip/7z2600-x64.exe` | Windows x64 | Admin silent installer > `C:\Program Files\7-Zip\` |
| `prebuilt-binaries/7zip/7z2600-extra.7z` | Windows x64 | Contains `7za.exe` for user (portable) installs |
| `prebuilt-binaries/7zip/7z2600-linux-x64.tar.xz` | Linux x86-64 | Contains `7zz` binary for admin and user installs |

## Install Matrix

| Mode | Windows | Linux |
|------|---------|-------|
| **Admin** | `C:\Program Files\7-Zip\7z.exe` (requires elevation) | `/usr/local/bin/7zz` (requires root) |
| **User** | `%LOCALAPPDATA%\airgap-cpp-devkit\7zip\7za.exe` (no elevation) | `~/.local/bin/7zz` (no root) |

## Usage

```bash
# From repo root -- install mode is auto-detected
bash dev-tools/7zip/setup.sh

# Force a custom prefix
bash dev-tools/7zip/setup.sh --prefix /opt/tools/7zip
```

The install mode (admin/user/custom) is resolved by `scripts/install-mode.sh` -- the same
mechanism used by all other modules in this devkit.

## Windows Notes

**Admin install** runs the official 7-Zip installer silently (`/S` flag). The installer
adds `C:\Program Files\7-Zip` to the system PATH automatically. Open a new terminal
after install for PATH to take effect.

**User install** extracts `7za.exe` from the extra package -- this is a standalone
console-only executable that requires no installation. It does not support the GUI.
`7za.exe` supports the most common formats (7z, zip, tar, gz, xz, bz2). For full
format support including RAR extraction, use the admin install (`7z.exe`).

## Linux Notes

The tarball contains two binaries:
- `7zz` -- full build with codec support (2.88 MB) -- **this is what we install**
- `7zzs` -- statically linked standalone (3.76 MB) -- not installed

After install, verify with:
```bash
7zz i
```

Note: `7zz` does not support `--version`. Use `7zz i` to print version and capability info.

## Upstream

- Version: 26.00 (2026-02-12)
- Author: Igor Pavlov
- License: LGPL-2.1-or-later with unRAR restriction
- Source: https://www.7-zip.org / https://github.com/ip7z/7zip