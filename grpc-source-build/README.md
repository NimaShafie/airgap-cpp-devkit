# grpc-source-build

Vendored gRPC v1.76.0 source tree for air-gapped Windows environments.
Part of the `airgap-cpp-devkit` suite.

## Pinned Release

| Component   | Version  |
|-------------|----------|
| gRPC        | 1.76.0   |
| protobuf    | bundled  |
| abseil-cpp  | bundled  |
| boringssl   | bundled  |
| re2         | bundled  |
| zlib        | bundled  |
| c-ares      | bundled  |

Upstream: [grpc/grpc v1.76.0](https://github.com/grpc/grpc/releases/tag/v1.76.0)

This is a **flat source extraction** — all `third_party/` dependencies are
included inline. No git submodules, no network access required to extract
or build.

---

## Quickstart

```bash
cd grpc-source-build
bash setup.sh
```

That's it for extraction. Then build on Windows:

```powershell
# Open Developer PowerShell for VS 2022
.\setup_grpc.bat
```

---

## How It Works

The gRPC source tree (407MB uncompressed) compresses to ~89MB as a `.tar.gz`
and fits in a single committed part in `vendor/`.

`setup.sh` runs the following in sequence:

```
verify.sh       -- SHA256-checks the part against manifest.json
reassemble.sh   -- joins part(s) into the .tar.gz, verifies result
                   (single-part for v1.76.0, multi-part ready for future)
tar -xzf        -- extracts to src/grpc_unbuilt_v1.76.0/ by default
```

---

## Build Instructions (Windows)

Prerequisites:
- Visual Studio 2022 with "Desktop development with C++" workload
- CMake ≥ 3.16
- MSVC ≥ 19.44

After `bash setup.sh`, open **Developer PowerShell for VS 2022**:

```powershell
cd <path-to-setup_grpc.bat>
.\setup_grpc.bat
```

This installs gRPC to `C:\Users\Public\FTE_Software\grpc-1.76.0` and builds
the HelloWorld demo on your Desktop.

### Manual CMake steps

```powershell
cd src\grpc_unbuilt_v1.76.0
mkdir cmake\build
cd cmake\build
cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF `
      -DCMAKE_CXX_STANDARD=17 `
      -DCMAKE_INSTALL_PREFIX="C:\Users\Public\FTE_Software\grpc-1.76.0\bin" `
      ..\..
cmake --build . --config Release --target install
```

---

## Custom Extract Location

By default `setup.sh` extracts to `grpc-source-build/src/`. To extract
elsewhere (e.g. the path `setup_grpc.bat` expects):

```bash
bash setup.sh "C:/Users/Public/FTE_Software"
# Result: C:/Users/Public/FTE_Software/grpc_unbuilt_v1.76.0/
```

---

## Integrity

SHA256 is pinned in `manifest.json` and was self-computed from the vendored
tarball at time of pinning. gRPC does not publish official checksums for
source archives.

| File | SHA256 |
|------|--------|
| `grpc_unbuilt_v1.76.0.tar.gz.part-aa` | `000a283359a03581c4e944a67d295ba52b760532877efbe605b4bf49a303a8d3` |
| `grpc_unbuilt_v1.76.0.tar.gz` (reassembled) | `000a283359a03581c4e944a67d295ba52b760532877efbe605b4bf49a303a8d3` |

---

## Layout

```
grpc-source-build/
├── setup.sh               <- single user entry point
├── manifest.json          <- version pin + SHA256 hashes
├── setup_grpc.bat         <- Windows CMake build script (copy here from grpc/)
├── scripts/
│   ├── verify.sh          <- offline integrity check
│   ├── reassemble.sh      <- joins parts into .tar.gz, verifies
│   └── (no install.sh)    <- extraction handled directly by setup.sh
├── vendor/
│   └── *.part-aa          <- committed to git (~89MB)
└── src/                   <- extracted here by setup.sh (gitignored)
    └── grpc_unbuilt_v1.76.0/
```

---

## Notes

- **`vendor/*.tar.gz` is gitignored.** Only `*.part-*` files are committed.
- **`src/` is gitignored.** The extracted tree is never committed.
- **Windows only.** The `setup_grpc.bat` build script targets MSVC/Visual
  Studio 2022. Linux build support is not included in this module.
