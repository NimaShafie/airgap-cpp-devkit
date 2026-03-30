# frameworks/grpc

### Author: Nima Shafie

Vendored gRPC source build and prebuilt binaries for air-gapped Windows
environments. Part of the `airgap-cpp-devkit` suite.

---

## Vendored Versions

| Version | Status | Source Bundle | SHA256 (reassembled) |
|---------|--------|---------------|----------------------|
| **v1.78.1** | ✅ Production-tested | 127MB (3 parts) | `99a8d16ad8aa9ced75d255e1e92247de556e91483fd0e0e73c158a76c9913871` |

The source bundle is a full recursive clone — all `third_party/` dependencies
(protobuf, abseil-cpp, boringssl, re2, zlib, c-ares, and all nested submodules)
are included inline. No git submodules, no network access required to build.

---

## Quickstart — Prebuilt (Recommended)

No compiler or Visual Studio required for installation. Just extract and use.

**Step 1 — Install from prebuilt:**
```powershell
cd frameworks\grpc
.\install-prebuilt.ps1 -version 1.78.1
```

**Step 2 — Run the HelloWorld demo:**
```powershell
.\setup.ps1 -version 1.78.1
```

The demo builds and launches `greeter_server.exe` + `greeter_client.exe`
automatically. Expected output: `Greeter received: Hello world`.

---

## Quickstart — Source Build

Builds gRPC from the vendored source tarball using MSVC. Takes ~40 minutes.

**From Developer PowerShell:**
```powershell
cd frameworks\grpc
.\setup.ps1 -version 1.78.1 -dest "C:\MyPath\grpc-1.78.1"
```

**From Git Bash (auto-detects VS environment):**
```bash
bash frameworks/grpc/setup.sh --version 1.78.1
```

---

## What `setup.ps1` Does

Single entry point for both prebuilt and source build paths:

```
1. Verifies vendored source parts (SHA256 vs manifest.json)
2. Reassembles grpc-1.78.1.tar.gz from split parts
3. Extracts source tree to src/grpc-1.78.1/
4. Detects install type:
   a. Prebuilt layout (bin/ present) → populates outputs/ and skips build
   b. No binaries → runs full source build via MSVC + Ninja + cmake
5. Copies HelloWorld demo files from install dir or source tree
6. Patches CMakeLists.txt proto path
7. Generates protobuf sources via protoc + grpc_cpp_plugin
8. Builds HelloWorld demo (Ninja + MSVC)
9. Launches greeter_server.exe + greeter_client.exe
```

**Air-gap cmake flags (source build only):**
```
-DFETCHCONTENT_FULLY_DISCONNECTED=ON
-DgRPC_ABSL_PROVIDER=module
-DgRPC_CARES_PROVIDER=module
-DgRPC_PROTOBUF_PROVIDER=module
-DgRPC_RE2_PROVIDER=module
-DgRPC_SSL_PROVIDER=module
-DgRPC_ZLIB_PROVIDER=module
```
All dependencies are sourced from `third_party/` — no network access.

---

## Call Chain

```
setup.sh  (bash entry point)
  └── setup.bat  (thin PowerShell launcher)
        └── setup.ps1  (all logic)
```

`setup.sh` is the entry point when running from Git Bash.
`setup.ps1` can also be invoked directly from Developer PowerShell.

---

## Requirements

### Prebuilt install (`install-prebuilt.ps1`)
- Any PowerShell
- 7-Zip (auto-detected; falls back to `prebuilt-binaries/dev-tools/7zip/`)
- No compiler, no Visual Studio, no CMake required

### Source build (`setup.ps1`)
- Visual Studio 2019 / 2022 / Insiders with Desktop C++ workload
- CMake ≥ 3.16 (at `C:\Program Files\CMake\bin\cmake.exe`)
- Git Bash (`bash.exe` on PATH)

---

## Install Locations

| Mode | Path |
|------|------|
| Admin (default) | `C:\Program Files\airgap-cpp-devkit\grpc-1.78.1\` |
| User | `%LOCALAPPDATA%\airgap-cpp-devkit\grpc-1.78.1\` |
| Custom | Pass `-dest <path>` to `setup.ps1` or `install-prebuilt.ps1` |

---

## Prebuilt Package

The prebuilt binaries live in `prebuilt-binaries/frameworks/grpc/windows/1.78.1/`
and contain the full `cmake --target install` output:

| Directory | Contents |
|-----------|----------|
| `bin/` | `protoc.exe`, `grpc_cpp_plugin.exe`, all language plugins |
| `include/` | All headers (grpc++, protobuf, abseil, etc.) |
| `lib/` | Static `.lib` files for all gRPC components and dependencies |
| `share/` | CMake config files (`find_package(gRPC)` support) |

Available as `.7z` (69MB, 2 parts) and `.zip` (162MB, 4 parts).
`install-prebuilt.ps1` auto-selects `.7z` if 7-Zip is available.

---

## Manual CMake Steps

If you prefer to build manually after extracting the source:

```powershell
cd src\grpc-1.78.1
mkdir cmake\build
cd cmake\build
cmake -G Ninja `
      -DCMAKE_BUILD_TYPE=Release `
      -DCMAKE_CXX_STANDARD=17 `
      -DCMAKE_INSTALL_PREFIX="C:\MyPath\grpc-1.78.1" `
      -DgRPC_INSTALL=ON `
      -DgRPC_BUILD_TESTS=OFF `
      -DFETCHCONTENT_FULLY_DISCONNECTED=ON `
      -DgRPC_ABSL_PROVIDER=module `
      -DgRPC_CARES_PROVIDER=module `
      -DgRPC_PROTOBUF_PROVIDER=module `
      -DgRPC_RE2_PROVIDER=module `
      -DgRPC_SSL_PROVIDER=module `
      -DgRPC_ZLIB_PROVIDER=module `
      ..\..
cmake --build . --target install -j 4
```

---

## Integrity

SHA256 hashes are pinned in `manifest.json` for all vendor parts.
`scripts/verify.sh` and `scripts/reassemble.sh` check parts before
any extraction or build. Both are called automatically by `setup.ps1`.

---

## Layout

```
frameworks/grpc/
├── setup.bat              <- thin launcher (calls setup.ps1)
├── setup.ps1              <- full build + demo pipeline
├── setup.sh               <- bash entry point (calls setup.bat)
├── install-prebuilt.ps1   <- extracts prebuilt from prebuilt-binaries/
├── manifest.json          <- SHA256 pins for vendored source parts
├── README.md
├── scripts/
│   ├── verify.sh          <- SHA256 check (accepts version arg)
│   └── reassemble.sh      <- joins parts into .tar.gz (accepts version arg)
├── vendor/                <- split .tar.gz parts committed to git
│   ├── grpc-1.78.1.tar.gz             <- reassembled tarball (gitignored)
│   ├── grpc-1.78.1.tar.gz.part-aa     <- 45MB
│   ├── grpc-1.78.1.tar.gz.part-ab     <- 45MB
│   └── grpc-1.78.1.tar.gz.part-ac     <- 37MB
└── src/                   <- extracted here by setup.ps1 (gitignored)
    └── grpc-1.78.1/
```

---

## Notes

- **`vendor/*.tar.gz` is gitignored.** Only `*.part-*` files are committed.
- **`src/` is gitignored.** The extracted source tree is never committed.
- **Windows only.** `setup.ps1` targets MSVC. Linux build not supported.
- **VS 2019, 2022, and 2026 Insiders** all work — generator is Ninja,
  not a VS solution generator, so no version-specific cmake generator needed.
- **Prebuilt and source build are independent.** Either path produces a
  fully functional install at the same destination layout.