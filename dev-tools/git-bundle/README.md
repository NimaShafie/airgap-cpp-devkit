# dev-tools/git-bundle

### Author: Nima Shafie

Python scripts for transferring Git repositories — including super repositories
with deeply nested submodules at any depth — across air-gapped networks using
native Git bundle files.

Every branch, tag, and commit is preserved exactly as it exists on the source
network.  The scripts require only Python 3.11+ and Git 2.x.  No pip installs,
no compiled extensions, no internet access required at any point.

The workflow is intentionally minimal: one script creates the bundle archive on
the source side, the archive is physically transported to the destination
network on CD/DVD, and a second script restores the full repository tree on the
other side.  All exported repositories are left in a clean, air-gapped state
with no remote URLs configured.

---

## Table of Contents

1. [How it works](#how-it-works)
2. [Requirements](#requirements)
3. [Repository structure](#repository-structure)
4. [Before you start](#before-you-start)
   - [Finding your Python command](#finding-your-python-command)
   - [Opening a terminal](#opening-a-terminal)
   - [Tab completion](#tab-completion)
5. [Quick start](#quick-start)
6. [Updating an existing repository](#updating-an-existing-repository)
7. [Testing the scripts](#testing-the-scripts)
8. [What is preserved](#what-is-preserved)
9. [Logging](#logging)
10. [Troubleshooting](#troubleshooting)
11. [Platform compatibility](#platform-compatibility)

---

## How it works

```
SOURCE NETWORK                         DESTINATION NETWORK
────────────────────────────────       ─────────────────────────────────────
python bundle.py                       python export.py
     |                                      |
     v                                      v
YYYYMMDD_HHmm_import/  --CD/DVD-->  YYYYMMDD_HHmm_export/
  repo.bundle                          repo-name/
  services/svc-a.bundle                  services/svc-a/   (all branches)
  services/svc-b.bundle                  services/svc-b/
  ...                                    ...
  bundle_verification.txt
  metadata.txt
```

1. `bundle.py` runs on the source network.  It recursively discovers every
   submodule, including those that only exist on non-default branches.  It
   fetches all refs and creates one `.bundle` file per repository.  A SHA256
   verification log and metadata file are written alongside the bundles.

2. The entire `YYYYMMDD_HHmm_import/` folder is burned to CD/DVD and physically
   transported to the destination network.

3. `export.py` runs on the destination network.  It verifies SHA256 checksums,
   clones the super repository from the bundle, and recursively restores every
   submodule in the correct nested folder structure.  All repositories are left
   with no remote URLs configured.

---

## Requirements

| Tool   | Minimum version |
|--------|-----------------|
| Python | 3.11            |
| Git    | 2.x             |

No additional packages are needed.  All imports are from the Python standard
library: `subprocess`, `pathlib`, `hashlib`, `shutil`, `datetime`.

---

## Repository structure

```
dev-tools/git-bundle/
├── bundle.py                  # Step 1 — run on the source network
├── export.py                  # Step 2 — run on the destination network
├── sync.py                    # Optional — update an existing exported repo
├── tests/
│   ├── create_test_repo.py    # Creates a local test fixture
│   ├── verify_test.py         # Verifies a completed bundle + export run
│   └── test_repos/            # Created by create_test_repo.py (not committed)
│       ├── full-test-repo/
│       └── full-test-base-*/
├── README.md
└── SYNC_WORKFLOW.md
```

---

## Before you start

### Finding your Python command

Windows does not always register `python` as a recognised command.  Before
running any script, open a terminal and test each of the following until one
prints a version number:

```
python --version
python3 --version
py --version
```

| Command    | When you see it                                                    |
|------------|--------------------------------------------------------------------|
| `python`   | Python was installed and added to PATH (most Linux installs, some Windows installs via the Microsoft Store or the official installer with "Add to PATH" ticked) |
| `python3`  | Common on Linux when both Python 2 and Python 3 are installed      |
| `py`       | Windows Python Launcher — installed automatically by the official Python installer on Windows regardless of PATH settings |

The output will look something like this:

```
C:\> py --version
Python 3.14.0
```

Whichever command works is the one to use everywhere this guide says `python`.
For example, if `py` is your working command:

```
py bundle.py
py tests/create_test_repo.py
```

If none of the three commands work, Python is not installed.
Download the installer from https://www.python.org/downloads/ and re-run the
test above after installing.

### Opening a terminal

You have three options on Windows.  All three work with these scripts.

**Command Prompt (cmd.exe)**

Press `Win + R`, type `cmd`, press Enter.
Or search for "Command Prompt" in the Start menu.

Navigate to the project folder:
```
cd C:\Users\YourName\Desktop\dev-tools/git-bundle
```

**PowerShell**

Press `Win + X` and select "Terminal" or "Windows PowerShell".
On Windows 11, the Windows Terminal app opens PowerShell by default.

Navigate to the project folder:
```
cd C:\Users\YourName\Desktop\dev-tools/git-bundle
```

**Git Bash**

If Git for Windows is installed, right-click anywhere in Windows Explorer
and select "Git Bash Here".  Alternatively, search for "Git Bash" in the
Start menu.

Navigate to the project folder using forward slashes:
```
cd ~/Desktop/dev-tools/git-bundle
```

On Linux, open the Terminal application and navigate the same way:
```
cd ~/Desktop/dev-tools/git-bundle
```

### Tab completion

Tab completion lets you press Tab to auto-complete file and script names
instead of typing them in full.

| Terminal    | Tab behaviour                                                                 |
|-------------|-------------------------------------------------------------------------------|
| cmd.exe     | Tab cycles through matches in the current directory.  Works for simple filenames but can be unreliable for subdirectory paths like `tests\create_test_repo.py`. |
| PowerShell  | Tab completes filenames and folder names.  Press `Ctrl + Space` to show all matching options at once.  More reliable than cmd.exe for subdirectory paths. |
| Git Bash    | Full bash-style completion.  Tab once completes unambiguous matches; Tab twice shows all options.  Works well for both filenames and subdirectory paths. |

For the best day-to-day experience, use PowerShell or Git Bash.

---

## Quick start

> **First time using these scripts?**
> It is strongly recommended to run the test workflow first on a safe local
> fixture before pointing these scripts at a real repository.
> Jump directly to [Testing the scripts](#testing-the-scripts).

### 1 — Configure bundle.py

Open `bundle.py` in any text editor.  Find the USER CONFIGURATION section near
the top:

```python
# ─────────────────────────────────────────────────────────────────────────────
#  USER CONFIGURATION
#
#  Change REPO_PATH to point at the Git super repository you want to bundle.
#
#  Windows example  ->  a folder called "my-project" on your Desktop:
#      REPO_PATH = Path(r"C:\Users\YourName\Desktop\my-project")
#
#  Linux example  ->  same idea:
#      REPO_PATH = Path.home() / "Desktop" / "my-project"
#
#  The default below points at the test repository created by running:
#      python tests/create_test_repo.py
#  No changes needed if you just want to test the workflow first.
# ─────────────────────────────────────────────────────────────────────────────
REPO_PATH = Path(__file__).parent / "tests" / "test_repos" / "full-test-repo"
```

Change the `REPO_PATH` line to point at your super repository.  The remote Git
address is detected automatically from the repository itself — no manual entry
needed.

**Windows example** — a repository called `my-project` on the Desktop:
```python
REPO_PATH = Path(r"C:\Users\YourName\Desktop\my-project")
```

Always use a raw string on Windows (the `r` prefix before the quote) so that
backslashes are not misread as escape characters.

**Linux example:**
```python
REPO_PATH = Path.home() / "Desktop" / "my-project"
```

`REPO_PATH` must point at the root of a Git repository — the folder that
directly contains `.git/`.

### 2 — Run bundle.py

```
python bundle.py
```

Console output example:

```
[INFO] Source : C:\Users\YourName\Desktop\my-project
[INFO] Output : C:\Users\YourName\Desktop\dev-tools/git-bundle\20260309_1430_import

[INFO] Discovering repositories...
[INFO] Found 6 repositories (super repo + 5 submodule(s))

[INFO] [1/6] [my-project] : (super repository)
[OK]   [1/6] [my-project] : 4 branches, 3 tags, 247 commits, 8M
[INFO] [2/6] [user-service] : services/user-service
[OK]   [2/6] [user-service] : 4 branches, 3 tags, 12 commits, 1M
...
[OK]   Bundled 6/6 repositories
[OK]   Total size  : 42M
[OK]   Output      : 20260309_1430_import/
[OK]   Time        : 0m 18s
```

### 3 — Verify the bundle log

**Windows (cmd.exe or PowerShell):**
```
type 20260309_1430_import\bundle_verification.txt
```

**Git Bash or Linux:**
```
cat 20260309_1430_import/bundle_verification.txt
```

Confirm every entry shows `Verification : VERIFIED` before transferring.

### 4 — Transfer to the destination network

Burn the entire `YYYYMMDD_HHmm_import/` folder to CD/DVD (physical media only)
and transport it to the destination machine.  Copy `export.py` alongside it.

### 5 — Run export.py

```
python export.py
```

The script auto-detects the most recent `*_import/` folder in the same
directory.  To target a specific folder instead, set `IMPORT_FOLDER_OVERRIDE`
at the top of `export.py`:

```python
IMPORT_FOLDER_OVERRIDE = "20260309_1430_import"
```

Console output example:

```
[INFO] Import : 20260309_1430_import/
[INFO] Export : 20260309_1430_export/

[INFO] Verifying SHA256 checksums...
[OK]   All 6 bundle(s) verified

[INFO] [1/6] [my-project] : (super repository)
[OK]   [1/6] [my-project] : 4 branches, 3 tags
[INFO] [2/6] [user-service] : services/user-service
[OK]   [2/6] [user-service] : 4 branches, 3 tags
...
[OK]   Repository  : C:\...\20260309_1430_export\my-project
[OK]   Submodules  : 5 restored
[OK]   Time        : 0m 12s
```

### 6 — Verify the export

```
cd 20260309_1430_export\my-project
git log --oneline -5
git branch
git submodule status --recursive
```

---

## Updating an existing repository

Use `sync.py` when a repository already exists on the destination network and
you want to apply newer bundles on top of it.  See `SYNC_WORKFLOW.md` for the
full procedure.

**Warning:** `sync.py` overwrites all local changes.  A backup is created
automatically before syncing.

---

## Testing the scripts

Run this workflow before pointing the scripts at a real repository.  It creates
a fully self-contained local test fixture and then verifies the complete
bundle-and-export cycle against it.

### Step 1 — Create the test fixture

```
python tests/create_test_repo.py
```

This creates `tests/test_repos/full-test-repo/` — a super repository with a
deliberately complex submodule structure designed to exercise every code path:

```
full-test-repo/                              <- Super repo
  4 branches: main, develop, feature/api-gateway, release/2.0
  4 tags    : v1.0.0, v1.5.0, v2.0.0-dev, v2.0.0

  main branch:
    services/user-service/                   <- 4 branches, 3 tags
      lib/database/                          <- 3 branches, 2 tags
        utils/logger/                        <- 3 branches, 2 tags
    services/payment-service/                <- 4 branches, 3 tags
      lib/cache/                             <- 3 branches, 2 tags

  develop branch (different submodule set):
    services/user-service/
      lib/database/
        utils/logger/
      lib/feature-flags/                     <- develop-only nested submodule
    services/notification-service/           <- replaces payment-service on develop
```

Total unique repositories: 8 (1 super + 7 submodule repos)

The fixture is specifically designed to catch the hardest class of bug:
submodules that only appear on non-default branches.  `notification-service`
and `feature-flags-lib` only exist on `develop`, so they can only be found by
scanning all branch trees, not just the checked-out one.

### Step 2 — Run the full workflow

`REPO_PATH` in `bundle.py` already points at the test fixture by default.
No changes needed.

```
python bundle.py
python export.py
```

### Step 3 — Run verification

```
python tests/verify_test.py
```

Expected output when all checks pass:

```
  Passed : 42/42
  Failed : 0/42

  ALL CHECKS PASSED
```

The verify script checks:

| Check | What is verified |
|-------|-----------------|
| 1 | All expected `.bundle` files exist, including branch-specific submodules |
| 2 | SHA256 values in `bundle_verification.txt` match the actual bundle files |
| 3 | Every `.bundle` passes `git bundle verify` |
| 4-9 | Each exported repo has the correct branch count, tag count, and zero remotes |
| 10 | Default branch is checked out in each exported repo |
| 11 | Super repo tree declares the correct submodule set per branch |
| 12 | user-service tree declares the correct nested submodule sets per branch |
| 13 | Branch-only bundles (notification-service, feature-flags) were captured |

### Cleaning up

**Windows (cmd.exe or PowerShell):**
```
rmdir /s /q tests\test_repos
for /d %i in (*_import *_export) do rmdir /s /q "%i"
```

**Git Bash or Linux:**
```
rm -rf tests/test_repos/ *_import/ *_export/
```

---

## What is preserved

| Git data | Preserved |
|---|---|
| All local branches | Yes |
| All tags | Yes |
| Full commit history | Yes |
| Remote-tracking refs | Yes — materialized as local branches, then origin is removed |
| Submodules at any depth | Yes |
| Submodules on non-default branches | Yes — cross-branch tree scan |
| Remote URL | Yes — auto-detected and written to metadata, then removed from exported repo |

---

## Logging

Console output uses a consistent four-tag format:

```
[INFO] [N/total] [repo-name] : informational message
[OK]   [N/total] [repo-name] : 4 branches, 2 tags, 312 commits, 5M
[WARN] [N/total] [repo-name] : non-fatal issue
[ERR]  [N/total] [repo-name] : failure reason
```

Log files are written alongside the bundles:

- `bundle_verification.txt` — SHA256, branch list, tag list, commit count,
  and file size for every bundled repository.
- `export_log.txt` — step-by-step record of the export and submodule
  restoration process.

---

## Troubleshooting

**python / python3 / py — which one do I use?**

See [Finding your Python command](#finding-your-python-command).  Run
`python --version`, `python3 --version`, and `py --version` in your terminal.
Use whichever one prints a version number.

**`REPO_PATH` not found**

Edit `REPO_PATH` at the top of `bundle.py` so it points at the folder
that directly contains `.git/`.  On Windows, use a raw string:
`Path(r"C:\full\path\to\your\repo")`.

**SHA256 verification fails on export**

The bundle files may have been corrupted during the physical transfer.
Re-burn to CD/DVD, re-copy, and re-run `export.py`.  To skip SHA checking
for diagnosis only, set `STRICT_SHA_VERIFY = 0` in `export.py`.

**A submodule is missing from the export**

Open `bundle_verification.txt` and look for any entry showing
`Status : NOT INITIALIZED / MISSING`.  This means the submodule could not
be initialized on the source side before bundling.  Ensure the source machine
can reach the submodule's remote URL, then re-run `bundle.py`.

**Windows path issues**

Use a raw string to avoid backslash misinterpretation:
```python
REPO_PATH = Path(r"C:\Users\YourName\Desktop\my-project")
```

**Branch not checked out after export**

`export.py` checks out the first of `main`, `develop`, or `master` it finds.
If your default branch has a different name, the first local branch
alphabetically will be checked out instead.

---

## Platform compatibility

| Platform | Supported |
|---|---|
| Windows 10 / 11 | Yes — native Python, no Git Bash required |
| Linux RHEL 8 | Yes — requires Python 3.11 installed separately |
| Linux Ubuntu | Yes |

---

**Last updated:** March 2026
**Tested with:** Python 3.14.0, Git 2.x, Windows 11