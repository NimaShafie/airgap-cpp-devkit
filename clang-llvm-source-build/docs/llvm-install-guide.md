← [Back to README](../README.md)

# LLVM Build Prerequisites
### `clang-llvm-style-formatter`

`clang-format` is compiled from the vendored source in `llvm-src/` by
`scripts/build-clang-format.sh`. This document lists what must already be
present on the developer's machine for that build to succeed.

**No network access is required.** The source is already in `llvm-src/`.

---

## Windows 11

### Required

| Tool | Minimum | How to confirm |
|------|---------|---------------|
| Visual Studio 2017, 2019, or 2022 | With C++ workload | `cl.exe` on PATH in a VS Command Prompt |
| CMake | 3.14 | `cmake --version` |
| Ninja *(recommended)* | Any | `ninja --version` |

### Notes

CMake and Ninja are bundled with Visual Studio 2019 and 2022 — no separate
installation needed if VS is present.

The build script must be run from a shell where the MSVC compiler is on PATH.
The most reliable way is the **x64 Native Tools Command Prompt for VS 20xx**
(found in the Start menu under your VS installation). From Git Bash, you can
also source the VS environment:

```bash
# VS 2022 example — adjust path to your edition
cmd.exe /c '"C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" && bash'
```

Then run:
```bash
bash .llvm-hooks/scripts/build-clang-format.sh
```

Build time: approximately 30–45 minutes with Ninja on a modern machine.

---

## RHEL 8

### Required

| Tool | Minimum | Install if missing |
|------|---------|-------------------|
| GCC / G++ | 8.x | `sudo dnf groupinstall "Development Tools"` |
| CMake | 3.14 | `sudo dnf install cmake` |
| Ninja *(recommended)* | Any | `sudo dnf install ninja-build` |
| Python 3 | 3.6 | Pre-installed on RHEL 8 |

If your RHEL 8 machine is air-gapped and these packages are not installed,
they must be provisioned by your sysadmin before building. Provide them with
this package list: `gcc gcc-c++ cmake ninja-build`.

### Confirming prerequisites

```bash
gcc --version     # Need 8.x or newer
cmake --version   # Need 3.14 or newer
ninja --version   # Optional but recommended
```

Then run:
```bash
bash .llvm-hooks/scripts/build-clang-format.sh
```

Build time: approximately 45–60 minutes with Ninja on RHEL 8.

---

## What the Build Produces

The compiled binary is placed at:

- **Windows:** `bin/windows/clang-format.exe`
- **Linux:** `bin/linux/clang-format`

The pre-commit hook discovers these paths automatically via `find-tools.sh` —
no PATH configuration is needed after building.

The build directory (`llvm-src/build/`) can be deleted after a successful build
to reclaim approximately 420 MB of disk space:

```bash
rm -rf .llvm-hooks/llvm-src/build/
```

---

## Troubleshooting

### "cmake: not found" or "ninja: not found"

Install the missing tool (see the table above for your platform).
On Windows, verify you are running from a VS command prompt — not a plain
Git Bash window that lacks the MSVC environment.

### Build fails with "No C++ compiler found"

On Windows: open an x64 Native Tools Command Prompt for VS and rerun the
bootstrap from there.

On RHEL 8: confirm `g++` is installed (`which g++`). If absent, contact your
sysadmin to install `gcc-c++`.

### Build fails partway through (out of memory / disk)

The build needs approximately 4–5 GB of free disk space during compilation.
If disk is low, consider passing `--jobs 2` to limit parallelism and reduce
peak memory:

```bash
bash .llvm-hooks/scripts/build-clang-format.sh --jobs 2
```

### Already built, but hook can't find clang-format

Run:
```bash
bash .llvm-hooks/scripts/verify-tools.sh
```

If the binary exists at `bin/linux/clang-format` or `bin/windows/clang-format.exe`,
confirm it is executable (`chmod +x`) and rerun bootstrap:

```bash
bash .llvm-hooks/bootstrap.sh --force
```