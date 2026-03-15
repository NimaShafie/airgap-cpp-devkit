# airgap-cpp-devkit

Air-gapped C++ developer toolkit for network-restricted environments.

Provides two self-contained submodule tools that work without internet access,
without admin rights, and without pre-built binaries — everything builds from
vendored source.

---

## Tools

### `clang-llvm-style-formatter/`
Enforces LLVM C++ coding standards via a Git pre-commit hook.

- Vendored LLVM 22.1.1 source — builds `clang-format` from scratch
- Works on Windows 11 (Git Bash) and RHEL 8
- No admin rights required — installs per-user
- Pre-commit hook rejects commits that violate LLVM style
- Smoke test verifies the full pipeline after build

**Quick start:**
```bash
git submodule update --init --recursive
bash clang-llvm-style-formatter/bootstrap.sh
```

---

### `git-bundle/`
Transfers Git super-repositories with arbitrarily nested submodules
across air-gapped network boundaries.

- Bundles all branches, tags, commits, and refs
- Handles nested submodules recursively via BFS traversal
- Works on Windows 11 (MINGW64) and RHEL 8
- SHA256 manifest verification on import
- 58/58 tests passing

**Quick start:**
```bash
# Export (internet-connected side)
python3 git-bundle/bundle.py --repo <path> --out bundles/

# Import (air-gapped side)
python3 git-bundle/export.py --input bundles/ --out <target-path>
```

---

## Design principles

| Principle | How it's met |
|-----------|-------------|
| Air-gapped | All dependencies vendored in-repo as source tarballs |
| No binaries committed | Tools build from source on first use |
| No admin rights | Installs to per-user paths only |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Sysadmin friendly | Single bootstrap command, clear error messages |

---

## Requirements

### clang-llvm-style-formatter
| Platform | Requirements |
|----------|-------------|
| Windows 11 | Visual Studio 2017/2019/2022/Insider (C++ workload), CMake 3.14+, Git Bash |
| RHEL 8 | GCC 8+, CMake 3.14+, Python 3.6+ |

### git-bundle
| Platform | Requirements |
|----------|-------------|
| Windows 11 | Python 3.8+, Git 2.20+ |
| RHEL 8 | Python 3.6+, Git 2.20+ |

---

## Repository structure

```
airgap-cpp-devkit/
├── clang-llvm-style-formatter/   ← LLVM style enforcement submodule
│   ├── bootstrap.sh              ← one-command developer setup
│   ├── bin/windows/              ← built binaries (gitignored)
│   ├── llvm-src/                 ← vendored LLVM 22.1.1 source (split parts)
│   ├── ninja-src/                ← vendored Ninja 1.13.2 source
│   ├── config/                   ← .clang-format, .clang-tidy, hooks.conf
│   ├── hooks/pre-commit          ← the enforcement hook
│   └── scripts/                  ← build, extract, smoke-test, fix-format
└── git-bundle/                   ← air-gap transfer submodule
    ├── bundle.py                 ← export bundles
    ├── export.py                 ← import bundles
    ├── verify_test.py            ← test harness
    └── logs/                     ← timestamped run logs
```

---

## License

See individual submodule directories for license details.