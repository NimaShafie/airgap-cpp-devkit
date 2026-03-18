# clang-llvm-style-formatter

### Author: Nima Shafie

> Pre-commit hook enforcement of [LLVM Coding Standards](https://llvm.org/docs/CodingStandards.html)
> for C/C++ repositories — designed for air-gapped, multi-repo, multi-platform environments.

---

## What This Is

A self-contained submodule that installs `clang-format` from a vendored Python
wheel and wires a pre-commit hook into any host repository. Every `git commit`
is automatically checked against LLVM C++ style — no network access, no admin
rights, no pre-installed tools required beyond Python 3.8+.

**Install time: ~5 seconds. No compiler. No Visual Studio. No CMake.**

---

## Install — Choose Your Situation

### Situation A — Your production repo already has setup.sh at the root

This is the standard case after a maintainer has wired in the submodule.
Run once after cloning:

```bash
bash setup.sh
```

That is all. The hook is installed. Every subsequent `git commit` enforces
LLVM style automatically.

---

### Situation B — You have cloned this formatter directly (no setup.sh)

Run `bootstrap.sh` directly from inside the formatter directory:

```bash
# If you are working inside airgap-cpp-devkit:
bash clang-llvm-style-formatter/bootstrap.sh

# If you have cloned clang-llvm-style-formatter on its own:
bash bootstrap.sh
```

`bootstrap.sh` works with or without a surrounding git repository:
- **Inside a git repo** — installs clang-format and wires the pre-commit hook.
- **Outside a git repo** — installs clang-format only; prints instructions
  for installing the hook once you have a repo to target.

---

### Situation C — You are a maintainer adding this to a new production repo

See [For Maintainers](#for-maintainers--adding-to-a-new-production-repository) below.

---

## What bootstrap.sh Does

| Step | What happens | Git repo required? |
|------|-------------|-------------------|
| 1 | Initialises git submodules | Only if inside a git repo |
| 2 | Checks if `clang-format` is already available | No |
| 3 | If not found: installs from vendored `.whl` via pip/venv (~5 sec) | No |
| 4 | Installs pre-commit hook into `.git/hooks/pre-commit` | Only if inside a git repo |

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Python 3.8+, Git Bash (MINGW64) |
| RHEL 8 | Python 3.8+, Bash 4.x |

No compiler, no Visual Studio, no CMake, no internet access required.

---

## When a Commit Is Rejected

```
╔══════════════════════════════════════════════════════════════════╗
║  clang-format: LLVM style violations found — commit REJECTED    ║
╚══════════════════════════════════════════════════════════════════╝
    ✗  src/bad_indent.cpp

  Fix options:
    Auto-fix staged files:  bash tools/clang-llvm-style-formatter/scripts/fix-format.sh
    Manual:                 clang-format --style=file -i <file>
```

### Auto-fix and re-commit

```bash
bash tools/clang-llvm-style-formatter/scripts/fix-format.sh
git commit -m "your message"
```

### Preview only (no changes written)

```bash
bash tools/clang-llvm-style-formatter/scripts/fix-format.sh --dry-run
```

### Emergency bypass (use sparingly)

```bash
git commit --no-verify -m "emergency: skip formatting check"
```

---

## For Maintainers — Adding to a New Production Repository

Do this once per production repo. Developers only ever run `bash setup.sh`.

### Step 1 — Add the submodule under a `tools/` folder

```bash
cd your-cpp-project/

git submodule add \
    https://bitbucket.your-org.com/your-team/clang-llvm-style-formatter.git \
    tools/clang-llvm-style-formatter

git submodule update --init --recursive
```

### Step 2 — Copy setup.sh to the repo root

`setup.sh` is a ~50 line wrapper that lives at the root of each production
repo and delegates entirely to `bootstrap.sh`. Copy it from the template:

```bash
cp tools/clang-llvm-style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 — Add .gitignore entries

```bash
cat tools/clang-llvm-style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### Step 4 — Commit and push

```bash
git add .gitmodules tools/clang-llvm-style-formatter setup.sh .gitignore
git commit -m "chore: add LLVM C++ style enforcement"
git push
```

### What lands in your production repo

```
your-cpp-project/
├── setup.sh                          ← one file at root, run once per developer
├── .gitmodules                       ← auto-generated submodule pointer
├── tools/
│   └── clang-llvm-style-formatter/  ← submodule ref (zero bytes until init)
│       ├── bootstrap.sh
│       ├── python-packages/          ← vendored wheels (no network needed)
│       ├── config/                   ← style rules (.clang-format, .clang-tidy)
│       └── scripts/
└── ... (your project files)
```

### Keeping the submodule up to date

```bash
git submodule update --remote tools/clang-llvm-style-formatter
git add tools/clang-llvm-style-formatter
git commit -m "chore: update clang-llvm-style-formatter"
git push
```

---

## Verifying the Installation

```bash
# Full end-to-end smoke test (8 checks)
bash tools/clang-llvm-style-formatter/scripts/smoke-test.sh

# Tool discovery diagnostic
bash tools/clang-llvm-style-formatter/scripts/verify-tools.sh
```

Expected smoke test output:
```
  Results: 8 passed | 0 failed | 0 skipped
  All tests passed. The formatter is working correctly.
```

---

## Local Configuration Overrides (Per-Developer)

After running `setup.sh` or `bootstrap.sh`, a file is created at:
```
tools/clang-llvm-style-formatter/.llvm-hooks-local/hooks.conf
```

This file is gitignored — changes are local to your machine only:

```bash
# Show per-file diffs when a commit is rejected
VERBOSE="true"

# Override clang-format binary path
CLANG_FORMAT_BIN="/usr/bin/clang-format-17"

# Enable clang-tidy (requires compile_commands.json from CMake)
ENABLE_TIDY="true"
```

---

## Style Rules

Style rules live in `config/.clang-format` and `config/.clang-tidy` inside
the submodule. All production repos share the same rules — updating the
formatter submodule updates all repos at once.

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | Core install — works standalone or inside a git repo |
| `python-packages/` | Vendored `.whl` files — clang-format installs from here |
| `hooks/pre-commit` | The enforcement hook wired into `.git/hooks/` |
| `config/.clang-format` | LLVM style rules |
| `config/.clang-tidy` | Static analysis rules |
| `config/hooks.conf` | Default runtime configuration |
| `scripts/fix-format.sh` | Auto-format and re-stage failing files |
| `scripts/smoke-test.sh` | End-to-end verification |
| `scripts/verify-tools.sh` | Diagnostic: tool locations and versions |
| `scripts/install-hooks.sh` | Wires hook into host repo (skips gracefully if no repo) |
| `scripts/install-venv.sh` | Creates venv, installs from wheel |
| `scripts/fetch-wheels.sh` | **[Maintainer]** Download wheels for a new version |
| `docs/gitignore-snippet.txt` | Entries to add to consuming repo's `.gitignore` |
| `docs/production-repo-template/setup.sh` | Template `setup.sh` for production repos |
| `docs/production-repo-template/README.md` | Maintainer checklist |

---

## Supported Environments

| Environment | Status |
|-------------|--------|
| Windows 11 + Git Bash (MINGW64) | Supported |
| RHEL 8 + Bash 4.x | Supported |
| Visual Studio 2017 / 2019 / 2022 / Insider | Supported (hook runs via Git) |
| VxWorks Workbench | Hook runs on host OS shell; target unaffected |