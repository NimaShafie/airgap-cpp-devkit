# frameworks/grpc

### Author: Nima Shafie

Vendored gRPC source build for air-gapped Windows environments.
Supports multiple versions with a built-in version selector.
Part of the `airgap-cpp-devkit` suite.

---

## Vendored Versions

| Version | Status | Compressed Size | SHA256 (reassembled) |
|---------|--------|-----------------|----------------------|
| **v1.76.0** | ✅ Production-tested | ~89MB | `000a283359a03581c4e944a67d295ba52b760532877efbe605b4bf49a303a8d3` |
| **v1.78.1** | 🧪 Candidate-testing | ~15MB | `3bb18f315a09e5a14cd9d3b5b76529fd0cd8d4c52b02fee2d9f32e409e63934d` |

Both versions are flat source extractions — all `third_party/` dependencies
(protobuf, abseil-cpp, boringssl, re2, zlib, c-ares) are included inline.
No git submodules, no network access required to extract or build.

Upstream releases:
- [grpc/grpc v1.76.0](https://github.com/grpc/grpc/releases/tag/v1.76.0)
- [grpc/grpc v1.78.1](https://github.com/grpc/grpc/releases/tag/v1.78.1)

---

## Quickstart

Run `setup_grpc.bat` from a regular cmd or PowerShell window — it handles
everything automatically:

```cmd
cd frameworks/grpc
setup_grpc.bat
```

The script will prompt you to select a version:

```
============================================================
 gRPC Air-Gap Source Build
============================================================

 Available versions:
   [1] gRPC v1.76.0  (production-tested)
   [2] gRPC v1.78.1  (candidate-testing)

 Select version (1 or 2):
```

---

## What `setup_grpc.bat` Does

Single entry point — no separate bash invocation needed. Runs the full
pipeline in one shot:

```
1. Prompts for version selection
2. bash scripts/verify.sh <version>     -- SHA256-checks parts vs manifest
3. bash scripts/reassemble.sh <version> -- joins parts into .tar.gz, verifies
4. bash tar -xzf                        -- extracts to src/<extract_root>/
5. VsDevCmd.bat                         -- initializes VS 2022 Insiders env
6. xcopy                                -- copies source to FTE_Software\grpc-<version>
7. cmake configure + build + install    -- builds gRPC with MSVC
8. protoc                               -- generates HelloWorld protobuf sources
9. cmake (demo)                         -- builds HelloWorld demo
10. PowerShell (x2)                     -- launches greeter_server + greeter_client
```

**Requirements:**
- Git Bash (`bash.exe`) on PATH
- Visual Studio 2022 Insiders with Desktop C++ workload
- CMake ≥ 3.16 / MSVC ≥ 19.44

---

## Build Output Locations

| Item | Path |
|------|------|
| gRPC install (v1.76.0) | `C:\Users\Public\FTE_Software\grpc-1.76.0\` |
| gRPC install (v1.78.1) | `C:\Users\Public\FTE_Software\grpc-1.78.1\` |
| Build outputs | `<install>\outputs\bin\` and `outputs\lib\` |
| HelloWorld demo | `%USERPROFILE%\Desktop\grpc_demo\` |

---

## Manual CMake Steps

If you prefer to build manually after extraction:

```powershell
# v1.76.0
cd src\grpc_unbuilt_v1.76.0
mkdir cmake\build && cd cmake\build
cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF `
      -DCMAKE_CXX_STANDARD=17 `
      -DCMAKE_INSTALL_PREFIX="C:\Users\Public\FTE_Software\grpc-1.76.0" `
      ..\..
cmake --build . --config Release --target install

# v1.78.1
cd src\grpc-1.78.1
mkdir cmake\build && cd cmake\build
cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF `
      -DCMAKE_CXX_STANDARD=17 `
      -DCMAKE_INSTALL_PREFIX="C:\Users\Public\FTE_Software\grpc-1.78.1" `
      ..\..
cmake --build . --config Release --target install
```

---

## Integrity

SHA256 hashes are pinned in `manifest.json` and were self-computed from the
vendored tarballs at time of pinning. gRPC does not publish official checksums
for source archives.

`scripts/verify.sh` accepts a version argument and checks all parts for that
version against the manifest before any reassembly or extraction occurs.
`scripts/reassemble.sh` does the same before joining parts.

Both scripts are called automatically by `setup_grpc.bat` — integrity is
always verified before anything is extracted or built.

---

## Layout

```
frameworks/grpc/
├── setup_grpc.bat         <- single entry point (verify + extract + build)
├── manifest.json          <- SHA256 pins for all vendored versions
├── README.md
├── scripts/
│   ├── verify.sh          <- offline SHA256 check (accepts version arg)
│   └── reassemble.sh      <- joins parts into .tar.gz (accepts version arg)
├── vendor/                <- split .tar.gz parts committed to git
│   ├── grpc-1.76.0.tar.gz.part-aa     <- ~89MB (production-tested)
│   └── grpc-1.78.1.tar.gz.part-aa     <- ~15MB (candidate-testing)
└── src/                   <- extracted here by setup_grpc.bat (gitignored)
    ├── grpc_unbuilt_v1.76.0/
    └── grpc-1.78.1/
```

---

## Notes

- **`vendor/*.tar.gz` is gitignored.** Only `*.part-*` files are committed.
- **`src/` is gitignored.** The extracted tree is never committed.
- **Windows only.** `setup_grpc.bat` targets MSVC/Visual Studio 2022 Insiders.
  Linux build support is not included in this module.
- **`setup.sh` has been retired.** All functionality is now in `setup_grpc.bat`
  which handles both the bash extraction steps and the Windows CMake build in
  one unified script.
- **Both versions can coexist.** They install to separate directories under
  `C:\Users\Public\FTE_Software\` and do not conflict.