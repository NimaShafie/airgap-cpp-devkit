# prebuilt/

### Author: Nima Shafie

This directory groups all **pre-built binary packages** in `airgap-cpp-devkit`.

Pre-built packages differ from the other tools in this repo:

| Property          | Script/config tools              | Pre-built binary packages        |
|-------------------|----------------------------------|----------------------------------|
| Examples          | `toolchains/clang-style-formatter/`    | `winlibs-gcc-ucrt/`              |
|                   | `dev-tools/git-bundle/`                    |                                  |
| Binaries in repo? | No                               | No — vendored, gitignored        |
| How it works      | Bash/Python scripts              | Download → verify → extract      |
| Air-gap model     | Repo itself is the artifact      | `.7z`/`.zip` transferred via USB |
| Build from source | N/A or separate (`toolchains/clang-source-build/`) | Never — upstream pre-built only |

---

## Current Packages

| Package                 | Description                                      |
|-------------------------|--------------------------------------------------|
| `winlibs-gcc-ucrt/`     | GCC 15.2.0 + MinGW-w64 13.0.0 UCRT (Windows 64-bit) |

---

## Adding a New Package

Each package under `prebuilt/` follows this layout:

```
prebuilt/<package-name>/
├── manifest.json          # version pin, download URLs, SHA256 (multi-source)
├── scripts/
│   ├── download.sh        # online machine: fetch + verify
│   ├── verify.sh          # offline: hash check against manifest
│   ├── install.sh         # target: extract, smoke test
│   └── env-setup.sh       # source to activate in current shell
├── vendor/                # binary drop zone (gitignored)
│   └── .gitkeep
├── docs/
│   └── offline-transfer.md
├── .gitignore             # vendor/*.7z, vendor/*.zip, extracted dirs
└── README.md
```

The `winlibs-gcc-ucrt/` module is the reference implementation — copy its
structure and adapt `manifest.json` and the scripts for the new package.

### SHA256 verification policy

All packages must pin SHA256 in `manifest.json` cross-referenced from at
least **two independent sources** before being committed. Document those
sources in `manifest.json` under `sha256.sources`.
