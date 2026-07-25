# conan-airgap — portable offline Conan for air-gapped C/C++

Author: Nima Shafie

Bring [Conan](https://conan.io) **2.30.0** — the C/C++ package manager — into one
or many air-gapped environments. You seed the packages you need on a
network-connected machine, carry a single bundle across, and every isolated host
resolves dependencies **entirely from the local cache** with CMake and Eclipse
CDT integration.

This kit does not reinvent anything: it orchestrates Conan's own air-gap
primitives — `conan cache save` / `conan cache restore` (ship packages) and
`conan config install` (ship remotes/profiles/settings/plugins).

---

## Two machine roles

| Role | Has network? | Runs |
|------|--------------|------|
| **Seed** | Yes (can reach ConanCenter or your mirror) | `seed-export.sh`, `update-export.sh` |
| **Air-gapped target(s)** | No | `import-airgap.sh` |

---

## Layout

```
conan-airgap/
├── config/                 # `conan config install` payload
│   ├── remotes.json        #   default remotes (empty = offline)
│   ├── global.conf         #   base Conan settings
│   └── profiles/           #   build profiles (compiler/OS/arch)
│       ├── windows-msvc-x64        linux-gcc-rhel8-x64
│       ├── windows-mingw-x64       linux-gcc-rhel9-x64
│       ├── linux-clang-x64         linux-gcc-rhel10-x64
│       └── linux-gcc-devkit-x64
├── network/                # network-type overlays (pick one per host)
│   ├── offline/            #   zero remotes — pure cache
│   ├── internal-mirror/    #   internal Artifactory/Nexus
│   └── proxy/              #   internal repo via corporate proxy
├── requirements/baseline.txt   # the refs to seed (edit this)
├── templates/              # CMake + Eclipse consumer example
└── scripts/
    ├── seed-export.sh      # SEED:   fetch + pack a bundle
    ├── update-export.sh    # SEED:   pack an incremental delta bundle
    ├── import-airgap.sh    # TARGET: configure + restore cache + verify
    └── lib/conan-airgap.sh
```

---

## Workflow

### 1. Seed (network-connected machine)

Edit [`requirements/baseline.txt`](requirements/baseline.txt) to list the libraries
your teams build against, then:

```bash
bash scripts/seed-export.sh
# or narrow the targets:
bash scripts/seed-export.sh --requirements requirements/baseline.txt \
     --profiles linux-gcc-rhel9-x64,windows-msvc-x64
```

Produces `dist/conan-airgap-bundle-<stamp>.tar.gz` (+ `.sha256`) containing the
seeded recipes **and** binaries for every profile, plus the config and network
overlays.

> **Cross-platform note.** The seed machine downloads prebuilt binaries that
> ConanCenter publishes for each profile. For settings ConanCenter has no binary
> for, `--build=missing` builds *only what the seed host itself can build*. To
> seed binaries for a platform you can't build on (e.g. RHEL/Rocky 8, 9, or 10 binaries from a
> Windows seed), run `seed-export.sh` on a matching host and merge the bundles.

### 2. Transfer

Copy the `.tar.gz` and its `.sha256` to the air-gapped host via your approved
media/one-way transfer.

### 3. Import (each air-gapped host)

```bash
bash scripts/import-airgap.sh --bundle conan-airgap-bundle-<stamp>.tar.gz \
     --network offline
```

This verifies the bundle checksum, applies the config + the chosen **network
overlay**, restores the cache, and lists what's now available. Add
`--verify-ref fmt/10.2.1` to prove offline resolution.

---

## Network types (`--network`)

The same bundle adapts to different isolation levels — pick the overlay per host:

| `--network` | For | Effect |
|-------------|-----|--------|
| `offline` *(default)* | Fully isolated host | No remotes; cache only |
| `internal-mirror` | No internet, but an internal Artifactory/Nexus | Missing packages pulled from the internal repo |
| `proxy` | Internal repo reachable only via a corporate proxy | As above, through `core.net.http:proxies` |

Edit the URLs/proxy/CA in [`network/`](network/) before shipping (each folder has
a README). This is where you "store different profiles depending on the network."

---

## Updates & plugins

To push new libraries, version bumps, or Conan extensions without re-shipping
everything, put the new refs in a file and build a **delta** bundle:

```bash
# seed machine
echo "boost/1.84.0" > /tmp/new.txt
bash scripts/update-export.sh --requirements /tmp/new.txt
```

Import it exactly like a full bundle — `conan cache restore` is additive:

```bash
# air-gapped host
bash scripts/import-airgap.sh --bundle conan-airgap-update-<stamp>.tar.gz --network offline
```

Conan **extensions/plugins/hooks** and custom settings travel in `config/`
(they are installed by `conan config install`), so shipping an updated `config/`
in any bundle updates them on the target.

---

## Building with CMake and Eclipse

The kit configures Conan's `CMakeDeps` + `CMakeToolchain` generators, so seeded
dependencies drop straight into a CMake or Eclipse CDT project. See
[`templates/`](templates/) for a runnable example:

```bash
cd templates
bash build-cmake.sh   linux-gcc-rhel9-x64     # CMake presets (also CLion/VS/VS Code)
bash build-eclipse.sh linux-gcc-rhel9-x64     # generates an Eclipse CDT project
```

Conan emits `CMakeUserPresets.json`; `build-eclipse.sh` additionally drives
CMake's "Eclipse CDT4" generator to produce importable `.project`/`.cproject`.

---

## Linking Conan deps against the devkit's prebuilt gRPC

The devkit ships gRPC as a prebuilt package per MSVC toolset (see
[`tools/frameworks/grpc/`](../tools/frameworks/grpc/README.md)), built with the
**static CRT (`/MT`)**. To build an app that pulls libraries from this Conan kit
**and** links that prebuilt gRPC, your Conan deps must use the **same static
runtime** — otherwise you get `LNK2038 RuntimeLibrary mismatch`.

Three ABI-matched profiles ship for exactly this, one per gRPC toolset:

| Conan profile | gRPC package | Visual Studio |
|---------------|--------------|---------------|
| `windows-msvc-v142-grpc` | `grpc-1.83.0-msvc142-release` | Visual Studio 2019 |
| `windows-msvc-v143-grpc` | `grpc-1.83.0-msvc143-release` | Visual Studio 2022 (default) |
| `windows-msvc-v145-grpc` | `grpc-1.83.0-msvc145-release` | Visual Studio 2026 |

Seed and build with the profile that matches the gRPC toolset you installed:

```bash
# seed (connected)
bash scripts/seed-export.sh --profiles windows-msvc-v143-grpc
# build your app (air-gapped) — deps come from the cache, gRPC from the devkit
cd templates && bash build-cmake.sh windows-msvc-v143-grpc
```

The default `windows-msvc-x64` profile (dynamic `/MD`) remains for apps that do
**not** link the prebuilt gRPC.

## Requirements on the target

- Conan **2.30.0** (install via the devkit: `tools/dev-tools/conan/setup.sh`).
  The kit works with any Conan 2.x but warns on a version other than the target.
- For building: CMake + a compiler (both shipped by the devkit).
