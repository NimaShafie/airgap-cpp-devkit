# airgap-cpp-devkit

### Author: Nima Shafie

Air-gapped C++ developer toolkit for network-restricted environments.

All tools work without internet access, without admin rights, and without
pre-installed binaries. All dependencies are vendored and installed locally.

---

## Tools

| Directory | Purpose | Required? |
|-----------|---------|-----------|
| [`clang-llvm/style-formatter/`](clang-llvm/style-formatter/README.md) | Enforces LLVM C++ coding standards via Git pre-commit hook | Yes |
| [`clang-llvm/source-build/`](clang-llvm/source-build/README.md) | Optional: builds clang-format from LLVM 22.1.1 source (~30-60 min) | No |
| [`git-bundle/`](git-bundle/README.md) | Transfers Git repositories with nested submodules across air-gapped boundaries | Yes |
| [`lcov-source-build/`](lcov-source-build/README.md) | Code coverage reporting via lcov 2.4 + gcov, vendored Perl deps included | No |
| [`prebuilt/winlibs-gcc-ucrt/`](prebuilt/winlibs-gcc-ucrt/README.md) | Pre-built GCC 15.2.0 + MinGW-w64 13.0.0 UCRT toolchain for Windows | **No — standalone** |
| [`grpc-source-build/`](grpc-source-build/README.md) | Vendored gRPC source build for Windows (v1.76.0 production-tested, v1.78.1 candidate) | **No — standalone** |

---

## Can I skip `prebuilt/`, `grpc-source-build/`, or `lcov-source-build/`?

**Yes. All three are fully independent and optional.**

`prebuilt/winlibs-gcc-ucrt/` is a standalone GCC 15.2.0 toolchain for
developers who need to *compile C++ projects* in an air-gapped Windows
environment. It has no relationship to any other tool in this devkit:

- `clang-llvm/style-formatter/` — uses Python + pip wheels. No GCC dependency.
- `clang-llvm/source-build/` — uses the *system* compiler (MSVC/GCC already on
  the machine) to build clang-format from source. Not the WinLibs GCC.
- `git-bundle/` — pure Python. No compiler dependency.

`grpc-source-build/` is a standalone gRPC source tree for teams that need
gRPC in their air-gapped C++ projects. It has no relationship to any other
tool in this devkit. The entire build is self-contained — vendored source,
SHA256 verification, and a single `.bat` entry point that handles extraction,
VS environment init, CMake configure/build, and demo launch.

`lcov-source-build/` provides code coverage reporting for C++ projects compiled
with GCC's `-fprofile-arcs -ftest-coverage` flags. It vendors lcov 2.4 and all
required Perl dependencies (`Capture::Tiny`, `DateTime`, `DateTime::TimeZone`)
as pre-built tarballs — no internet access, no CPAN, no system Perl packages
beyond what RHEL 8 base provides.

If you only need the formatter and git transfer tool, ignore `prebuilt/`,
`grpc-source-build/`, and `lcov-source-build/` entirely.

`prebuilt/winlibs-gcc-ucrt/` ships as **committed pre-built binaries** (split
`.part-*` files). `grpc-source-build/` ships as **committed source archives**
(split `.part-*` files). `lcov-source-build/` ships as **committed pre-built
tarballs** (`lcov-2.4.tar.gz` + `perl-libs.tar.gz`). All use the same
vendor/manifest/SHA256 pattern.

---

## Who Reads What

This project serves two different audiences. Go to the section that applies to you.

### I am a developer on a production C++ repository

Your repo already has the formatter set up. You just need to run one command
after cloning:

```bash
bash setup.sh
```

That is all. See your repo's `setup.sh` for details, or see
[clang-llvm/style-formatter/README.md](clang-llvm/style-formatter/README.md)
for the full developer reference.

### I am a maintainer adding the formatter to a new production repo

See the [Deploying to Production Repositories](#deploying-to-production-repositories)
section below.

### I am working on the devkit itself

See [Development Setup](#development-setup) below.

---

## Deploying to Production Repositories

The formatter is designed to live as a submodule under `tools/` in each
production repo. Developers only ever run `bash setup.sh` — they never
interact with the submodule directly.

**What lands in each production repo:**
```
your-cpp-project/
├── setup.sh                              <- ~50 lines, the only new root file
├── .gitmodules                           <- 3-line auto-generated pointer
└── tools/
    └── style-formatter/                  <- submodule (a commit pointer, not a copy)
```

### Step 1 — Add the submodule (once per repo)

```bash
cd your-cpp-project/

git submodule add \
    https://bitbucket.your-org.com/your-team/airgap-cpp-devkit.git \
    tools/style-formatter

git submodule update --init --recursive
```

### Step 2 — Copy setup.sh into the repo root

```bash
cp tools/style-formatter/clang-llvm/style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 — Append .gitignore entries

```bash
cat tools/style-formatter/clang-llvm/style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### Step 4 — Commit and push

```bash
git add .gitmodules tools/style-formatter setup.sh .gitignore
git commit -m "chore: add LLVM C++ style enforcement"
git push
```

### What developers do after this (once per machine)

```bash
git clone <your-cpp-project-url>
cd your-cpp-project
bash setup.sh
```

Done. The hook is installed. Every subsequent `git commit` enforces LLVM style.

### Keeping the formatter up to date across all repos

When style rules or tooling are updated in the formatter repo, update each
production repo's submodule pointer:

```bash
git submodule update --remote tools/style-formatter
git add tools/style-formatter
git commit -m "chore: update clang-llvm style-formatter"
git push
```

Developers get the update on their next `git pull`.

---

## Development Setup

If you are working on the devkit itself (not deploying to a production repo):

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
bash clang-llvm/style-formatter/bootstrap.sh
```

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Python 3.8+, Git Bash (MINGW64) |
| RHEL 8 | Python 3.8+, Bash 4.x |

No compiler, no Visual Studio, no CMake required for the standard install.

### Install methods

**Method 1 — pip/venv (recommended, ~5 seconds)**
```bash
bash clang-llvm/style-formatter/bootstrap.sh
```
Installs `clang-format` from a vendored `.whl` file into a local Python venv.
No network access. No compiler. No admin rights.

**Method 2 — Build from LLVM source (optional, ~30-60 minutes)**
```bash
bash clang-llvm/source-build/bootstrap.sh
```
Compiles `clang-format` from the vendored LLVM 22.1.1 source tarball.
Use only if Python is unavailable or policy requires source builds.
Requires: Visual Studio (Windows) or GCC (Linux), CMake 3.14+.

**Method 3 — GCC toolchain for Windows (optional, pre-built binaries)**
```bash
cd prebuilt/winlibs-gcc-ucrt
bash setup.sh x86_64
source scripts/env-setup.sh x86_64
```
Installs GCC 15.2.0 + MinGW-w64 13.0.0 UCRT from vendored split archives.
Only needed if you require GCC to compile C++ projects on Windows.
Not required for the formatter or git transfer tool.

**Method 4 — gRPC for Windows (optional, source build)**
```cmd
cd grpc-source-build
setup_grpc.bat
```
Extracts vendored gRPC source, initializes VS 2022 Insiders environment,
builds with CMake, and launches the HelloWorld demo. Prompts for version
selection (v1.76.0 production-tested, v1.78.1 candidate).
Requires: Visual Studio 2022 Insiders with Desktop C++ workload, Git Bash.

**Method 5 — lcov code coverage (optional, RHEL 8 / Linux)**
```bash
bash lcov-source-build/bootstrap.sh
source lcov-source-build/scripts/env-setup.sh
```
Extracts vendored lcov 2.4 and Perl dependency tarballs. Sets `PERL5LIB` and
`PATH` so `lcov` and `genhtml` are immediately available. No internet access,
no CPAN, no EPEL required. System prerequisites (`perl-Time-HiRes`,
`perl-JSON`) are available in the RHEL 8 base AppStream repo.

---

## Design Principles

| Principle | How it is met |
|-----------|--------------|
| Air-gapped | All dependencies vendored in-repo (wheels, source tarballs, pre-built archives) |
| Minimal production footprint | One `setup.sh` + one submodule pointer per production repo |
| No admin rights | Installs to per-user/per-repo paths only |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Single entry point per tool | `bash bootstrap.sh` or `setup_grpc.bat` — nothing else required |
| Integrity verification | SHA256 pinned in `manifest.json` for all vendored archives, cross-referenced from independent sources where available |

---

## Repository Structure

```
airgap-cpp-devkit/
├── README.md                              <- you are here
├── sbom.spdx.json                         <- root aggregate SBOM (SPDX 2.3)
├── scripts/
│   └── generate-sbom.sh                   <- regenerates all SBOM timestamps
│
├── clang-llvm/                            <- LLVM/Clang tooling group
│   ├── style-formatter/                   <- LLVM style enforcement tool
│   │   ├── bootstrap.sh                   <- core install (called by setup.sh)
│   │   ├── sbom.spdx.json                 <- SPDX 2.3 SBOM
│   │   ├── python-packages/               <- vendored .whl files (committed)
│   │   ├── config/
│   │   │   ├── .clang-format              <- LLVM style rules
│   │   │   ├── .clang-tidy                <- static analysis rules
│   │   │   └── hooks.conf                 <- runtime defaults
│   │   ├── hooks/pre-commit               <- the enforcement hook
│   │   ├── scripts/                       <- install, verify, fix helpers
│   │   └── docs/
│   │       ├── gitignore-snippet.txt      <- append to production repo .gitignore
│   │       └── production-repo-template/
│   │           ├── setup.sh               <- copy to production repo root
│   │           └── README.md              <- maintainer checklist
│   │
│   └── source-build/                      <- optional LLVM source build
│       ├── bootstrap.sh                   <- builds clang-format from source
│       ├── manifest.json                  <- SHA256 pins for LLVM + Ninja sources
│       ├── sbom.spdx.json                 <- SPDX 2.3 SBOM
│       ├── llvm-src/                      <- vendored LLVM 22.1.1 (split parts)
│       │   ├── llvm-project-22.1.1.src.tar.xz.part-aa
│       │   └── llvm-project-22.1.1.src.tar.xz.part-ab
│       ├── ninja-src/                     <- vendored Ninja 1.13.2 source
│       │   └── ninja-1.13.2.tar.gz
│       ├── bin/
│       │   ├── windows/clang-format.exe   <- built output, not committed
│       │   └── linux/clang-format         <- built output, not committed
│       └── scripts/
│           ├── verify-sources.sh          <- SHA256 check LLVM + Ninja
│           └── reassemble-llvm.sh         <- joins LLVM parts into tarball
│
├── git-bundle/                            <- air-gap git transfer tool
│   ├── bundle.py
│   ├── export.py
│   ├── sbom.spdx.json                     <- SPDX 2.3 SBOM
│   └── tests/
│
├── lcov-source-build/                     <- code coverage reporting (Linux)
│   ├── bootstrap.sh                       <- extracts tarballs + verifies
│   ├── manifest.json                      <- SHA256 pins for lcov + perl-libs
│   ├── scripts/
│   │   ├── download.sh                    <- internet machine: populate vendor/
│   │   ├── verify.sh                      <- SHA256 + version check
│   │   └── env-setup.sh                   <- source to activate lcov in shell
│   └── vendor/
│       ├── lcov-2.4.tar.gz                <- vendored lcov 2.4 (committed, 1.1 MB)
│       └── perl-libs.tar.gz               <- vendored Perl deps (committed, 4.6 MB)
│
├── prebuilt/                              <- pre-built binary packages (OPTIONAL)
│   ├── README.md                          <- explains the prebuilt/ convention
│   └── winlibs-gcc-ucrt/                  <- GCC 15.2.0 + MinGW-w64 13.0.0 UCRT
│       ├── setup.sh                       <- single entry point: verify + install
│       ├── manifest.json                  <- SHA256 pins (dual-source verified)
│       ├── sbom.spdx.json                 <- SPDX 2.3 SBOM
│       ├── scripts/
│       │   ├── verify.sh                  <- offline integrity check
│       │   ├── reassemble.sh              <- joins split parts into .7z
│       │   ├── install.sh                 <- extracts toolchain
│       │   └── env-setup.sh               <- source to activate in current shell
│       ├── vendor/                        <- split .7z parts committed to git
│       │   ├── *.part-aa                  <- ~52MB
│       │   ├── *.part-ab                  <- ~52MB
│       │   └── *.part-ac                  <- ~2MB
│       └── docs/
│           └── offline-transfer.md
│
└── grpc-source-build/                     <- gRPC source build (OPTIONAL, Windows)
    ├── setup_grpc.bat                     <- single entry point: verify + extract + build
    ├── manifest.json                      <- SHA256 pins for all vendored versions
    ├── sbom.spdx.json                     <- SPDX 2.3 SBOM (pending)
    ├── README.md
    ├── scripts/
    │   ├── verify.sh                      <- offline integrity check (accepts version arg)
    │   └── reassemble.sh                  <- joins parts into tarball (accepts version arg)
    └── vendor/                            <- split .tar.gz parts committed to git
        ├── grpc-1.76.0.tar.gz.part-aa     <- ~89MB (production-tested)
        └── grpc-1.78.1.tar.gz.part-aa     <- ~15MB (candidate-testing)
```