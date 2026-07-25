# Consuming the air-gapped cache from CMake and Eclipse

A minimal, self-contained example that resolves `fmt` from the **local Conan
cache** (populated by the kit) and builds with **CMake**, or generates an
**Eclipse CDT** project. Nothing here touches the network.

Prereqs on the air-gapped host: Conan configured + cache restored (via
`scripts/import-airgap.sh`), plus CMake and a compiler (all shipped by the
devkit). `fmt/10.2.1` must have been seeded for your target profile.

## CMake (command line / any IDE that reads CMakePresets)

```bash
bash build-cmake.sh linux-gcc-rhel9-x64      # or windows-msvc-x64, etc.
```

What it does:
1. `conan install` with `--build=never` → writes `conan_toolchain.cmake`, the
   `CMakeDeps` files, and `CMakeUserPresets.json` from the cache.
2. `cmake --preset conan-release` + `cmake --build --preset conan-release`.

Because Conan emits `CMakeUserPresets.json`, this also works in **CLion**,
**VS Code (CMake Tools)**, and **Visual Studio** — they auto-detect the preset.

## Eclipse CDT

```bash
bash build-eclipse.sh linux-gcc-rhel9-x64     # Linux/RHEL
bash build-eclipse.sh windows-mingw-x64       # Windows
```

Defaults to the **Ninja-backed** Eclipse generator (`Eclipse CDT4 - Ninja`),
which works on both platforms — the devkit ships Ninja, and it avoids the
`make`/`sh.exe` pitfalls of the Makefiles backends. Pass a second argument to
override (e.g. `"Eclipse CDT4 - Unix Makefiles"`).

This drives CMake's **Eclipse CDT4** generator through Conan
(`tools.cmake.cmaketoolchain:generator`), producing `.project` / `.cproject`.
Import them with **File > Import > General > Existing Projects into Workspace**.
The Conan-generated toolchain feeds Eclipse's indexer the correct include paths,
so code completion resolves the air-gapped dependencies.

## Point it at real dependencies

Edit [`conanfile.txt`](conanfile.txt) `[requires]` to list the libraries your
project uses (they must be seeded), then re-run either build script.
