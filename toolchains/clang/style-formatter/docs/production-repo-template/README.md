# Production Repository Setup — toolchains/clang-style-formatter

### Author: Nima Shafie

This folder contains the files to copy into each production C++ repository
when adding LLVM style enforcement. It is a one-time maintainer action per
repo. Developers only ever run one command after that.

---

## Files in This Template

| File | Copy to | Purpose |
|------|---------|---------|
| `setup.sh` | Root of production repo | Single entry point for developer onboarding |

---

## Maintainer Checklist (once per production repo)

### 1 — Add the submodule

From the root of your production repo:

```bash
git submodule add \
    https://bitbucket.your-org.com/your-team/toolchains/clang-style-formatter.git \
    tools/toolchains/clang-style-formatter

git submodule update --init --recursive
```

### 2 — Copy setup.sh into the repo root

```bash
cp tools/toolchains/clang-style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### 3 — Append .gitignore entries

```bash
cat tools/toolchains/clang-style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### 4 — Commit everything

```bash
git add .gitmodules tools/toolchains/clang-style-formatter setup.sh .gitignore
git commit -m "chore: add LLVM C++ style enforcement"
git push
```

---

## Developer Onboarding (every developer, every new clone)

Tell developers to run one command after cloning:

```bash
bash setup.sh
```

That is the complete onboarding. They never need to know about submodules,
bootstrap scripts, or clang-format.

---

## What Gets Added to the Production Repo

```
your-cpp-project/
├── setup.sh              ← ~50 lines, the only new file at root
├── .gitmodules           ← auto-generated, 3 lines
└── tools/
    └── toolchains/clang-style-formatter/   ← submodule (a single commit pointer)
```

The submodule itself is not stored in your production repo — only a pointer
to a specific commit in the formatter repo. Running `setup.sh` pulls the
actual content down on demand.

---

## After Setup — Day-to-Day Developer Commands

| Situation | Command |
|-----------|---------|
| Commit rejected — auto-fix | `bash tools/toolchains/clang-style-formatter/scripts/fix-format.sh` |
| Commit rejected — preview only | `bash tools/toolchains/clang-style-formatter/scripts/fix-format.sh --dry-run` |
| Emergency bypass | `git commit --no-verify -m "message"` |
| Verify installation | `bash tools/toolchains/clang-style-formatter/scripts/smoke-test.sh` |
| Re-run setup (new machine) | `bash setup.sh` |
| Force reinstall | `bash setup.sh --force` |