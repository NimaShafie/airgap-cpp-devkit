# airgap-cpp-devkit

### Author: Nima Shafie

Air-gapped C++ developer toolkit for network-restricted environments.

All tools work without internet access, without admin rights, and without
pre-installed binaries. All dependencies are vendored and installed locally.

---

## Tools

| Directory | Purpose |
|-----------|---------|
| [`clang-llvm-style-formatter/`](clang-llvm-style-formatter/README.md) | Enforces LLVM C++ coding standards via Git pre-commit hook |
| [`clang-llvm-source-build/`](clang-llvm-source-build/README.md) | Optional: builds clang-format from LLVM source (~30-60 min) |
| [`git-bundle/`](git-bundle/README.md) | Transfers Git repositories with nested submodules across air-gapped boundaries |

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
[clang-llvm-style-formatter/README.md](clang-llvm-style-formatter/README.md)
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
├── setup.sh                              ← ~50 lines, the only new root file
├── .gitmodules                           ← 3-line auto-generated pointer
└── tools/
    └── clang-llvm-style-formatter/       ← submodule (a commit pointer, not a copy)
```

### Step 1 — Add the submodule (once per repo)

```bash
cd your-cpp-project/

git submodule add \
    https://bitbucket.your-org.com/your-team/clang-llvm-style-formatter.git \
    tools/clang-llvm-style-formatter

git submodule update --init --recursive
```

### Step 2 — Copy setup.sh into the repo root

```bash
cp tools/clang-llvm-style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 — Append .gitignore entries

```bash
cat tools/clang-llvm-style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### Step 4 — Commit and push

```bash
git add .gitmodules tools/clang-llvm-style-formatter setup.sh .gitignore
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
git submodule update --remote tools/clang-llvm-style-formatter
git add tools/clang-llvm-style-formatter
git commit -m "chore: update clang-llvm-style-formatter"
git push
```

Developers get the update on their next `git pull`.

---

## Development Setup

If you are working on the devkit itself (not deploying to a production repo):

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
bash clang-llvm-style-formatter/bootstrap.sh
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
bash clang-llvm-style-formatter/bootstrap.sh
```
Installs `clang-format` from a vendored `.whl` file into a local Python venv.
No network access. No compiler. No admin rights.

**Method 2 — Build from LLVM source (optional, ~30-60 minutes)**
```bash
bash clang-llvm-source-build/bootstrap.sh
```
Compiles `clang-format` from the vendored LLVM 22.1.1 source tarball.
Use only if Python is unavailable or policy requires source builds.
Requires: Visual Studio (Windows) or GCC (Linux), CMake 3.14+.

---

## Design Principles

| Principle | How it is met |
|-----------|--------------|
| Air-gapped | All dependencies vendored in-repo (wheels + source tarballs) |
| Minimal production footprint | One `setup.sh` + one submodule pointer per production repo |
| No admin rights | Installs to per-user/per-repo paths only |
| No pre-built binaries committed | pip wheel installs at bootstrap time |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Single entry point for developers | `bash setup.sh` — nothing else required |

---

## Repository Structure

```
airgap-cpp-devkit/
├── README.md                              ← you are here
│
├── clang-llvm-style-formatter/            ← LLVM style enforcement tool
│   ├── bootstrap.sh                       ← core install (called by setup.sh)
│   ├── python-packages/                   ← vendored .whl files (committed)
│   ├── config/
│   │   ├── .clang-format                  ← LLVM style rules
│   │   ├── .clang-tidy                    ← static analysis rules
│   │   └── hooks.conf                     ← runtime defaults
│   ├── hooks/pre-commit                   ← the enforcement hook
│   ├── scripts/                           ← install, verify, fix helpers
│   └── docs/
│       ├── gitignore-snippet.txt          ← append to production repo .gitignore
│       └── production-repo-template/
│           ├── setup.sh                   ← copy to production repo root
│           └── README.md                  ← maintainer checklist
│
├── clang-llvm-source-build/               ← optional LLVM source build
│   ├── bootstrap.sh                       ← builds clang-format from source
│   ├── llvm-src/                          ← vendored LLVM 22.1.1 (split parts)
│   ├── ninja-src/                         ← vendored Ninja 1.13.2
│   ├── bin/
│   │   ├── windows/clang-format.exe       ← built output, not committed
│   │   └── linux/clang-format             ← built output, not committed
│   └── scripts/
│
└── git-bundle/                            ← air-gap git transfer tool
    ├── bundle.py
    ├── export.py
    └── tests/
```