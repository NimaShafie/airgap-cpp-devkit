# Offline Transfer Guide -- toolchains/gcc/windows

### Author: Nima Shafie

This document describes how to move the WinLibs GCC UCRT toolchain across an
air-gap using physical media (USB drive, etc.).

---

## What to Transfer

After running `download.sh` on the networked (online) machine, the only file
you need to carry across is:

```
toolchains/gcc/windows/vendor/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r6.7z
```

(or the `i686` variant if you downloaded that instead)

The rest of the repository (scripts, manifest, docs) should already be present
on the air-gapped machine via the normal `dev-tools/git-bundle` transfer workflow.

---

## Step-by-Step

### 1. Online machine -- download and verify

```bash
cd toolchains/gcc/windows
bash scripts/download.sh x86_64
```

This will:
- Download the `.7z` into `vendor/`
- Verify SHA256 against the pinned manifest value
- Cross-check against the upstream GitHub `.sha256` sidecar

Both checks must pass before the file is considered ready.

### 2. Copy to transfer media

```bash
cp vendor/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r6.7z /media/usb/
```

### 3. On the air-gapped machine -- place the file

```bash
cp /media/usb/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r6.7z \
   toolchains/gcc/windows/vendor/
```

### 4. Verify integrity (offline, no network required)

```bash
cd toolchains/gcc/windows
bash scripts/verify.sh x86_64
```

This compares the file's SHA256 against the value pinned in `manifest.json`.
If this fails, do not proceed -- re-transfer the file.

### 5. Install

```bash
bash scripts/install.sh x86_64
```

This re-runs the verify step internally, then extracts to `toolchain/x86_64/`.

### 6. Activate for the current shell session

```bash
source scripts/env-setup.sh x86_64
gcc --version
```

---

## SHA256 Reference

The canonical checksum is pinned in `manifest.json` under `assets.x86_64.sha256.value`.

It was cross-referenced from two independent sources at the time of pinning:
1. The official GitHub release `.sha256` sidecar file from `brechtsanders/winlibs_mingw`
2. The `ScoopInstaller/Main` package registry (`bucket/mingw-winlibs.json`)

Both sources agreed on the same hash. If you ever need to re-pin for a new
release, run `download.sh` against the new tag and update `manifest.json`.

---

## Idempotency

- `download.sh` skips re-download if the file already exists in `vendor/` and
  immediately re-verifies it instead.
- `install.sh` removes a previous extraction before placing the new one, so
  re-running it is safe.
- `env-setup.sh` is idempotent -- sourcing it multiple times in the same shell
  will not duplicate the PATH entry.
