# Git Bundle Scripts for Air-Gapped Networks

This repository contains three bash scripts designed to bundle, export, and sync Git repositories with submodules (including nested submodules at any depth) across air-gapped networks.

## Overview

These scripts solve the problem of transferring a Git "super repository" (a repository containing multiple submodules) across network segments that cannot communicate with each other. The workflow involves:

1. **Bundling** - Creating git bundles of the entire repository structure on the source network
2. **Transfer** - Moving the bundles via physical media (CD/DVD/USB)
3. **Export/Sync** - Recreating or updating the repository structure on the destination network

## Key Features

✅ **Handles nested submodules** - Automatically discovers and bundles submodules at ANY depth  
✅ **Works without pre-initialization** - Detects submodules from `.gitmodules` files  
✅ **Three workflows** - Fresh export, update existing, or create new  
✅ **Windows & Linux compatible** - Tested on Windows Git Bash and Linux  
✅ **Smart branch detection** - Automatically checks out main, master, or default branch  
✅ **Comprehensive verification** - SHA256 checksums and detailed logging  
✅ **Preserves complete history** - All branches, tags, and commits included  
✅ **Air-gap ready** - No network dependencies after bundling  
✅ **Safe syncing** - Automatic backups when updating existing repositories  
✅ **Optimized performance** - Clean console output with full details in log files  
✅ **Time tracking** - Shows execution time for all operations  
✅ **Color-coded output** - Yellow info, green success, red errors for easy reading

## Performance

The scripts are highly optimized for speed and clarity:

**Console Output**:
- Minimal progress indicators and summaries only
- Branch/tag counts instead of listing each individually
- Clean, easy-to-read format with color coding
- Time tracking shows operation duration

**Log Files**:
- Complete details of all operations
- Every branch, tag, and commit recorded
- SHA256 checksums for verification
- Full audit trail

**Speed**:
- Typical execution: 30-60 seconds for most repositories
- Verbose git output suppressed (redirected to logs)
- Optimized terminal I/O for faster execution

**Example Console Output**:
```bash
ℹ [1/5] Bundling: modules/api-gateway
✓   ✓ Bundled (12 branches, 8 tags)
ℹ [2/5] Bundling: modules/database
✓   ✓ Bundled (6 branches, 4 tags)
...
✓ Time taken: 0m 45s
```

## Prerequisites

- Git installed on both source and destination systems
- `sha256sum` utility (typically included in coreutils)
- Bash shell (Git Bash on Windows, native bash on Linux)

## Scripts

### 1. bundle_all.sh

**Purpose**: Bundles a Git super repository with all its submodules for transfer to air-gapped networks.

**What it does**:
- Recursively scans and identifies ALL submodules at any depth
- Creates git bundles with full history (all branches, tags, commits)
- Maintains the exact folder structure of submodules
- Generates verification logs with SHA256 checksums
- Creates metadata files for the export process
- Optimized for speed with minimal console output
- Shows time taken for bundling operation

**Output**: Creates a timestamped folder `YYYYMMDD_HHmm_import/` containing all bundles

**Console Output**:
```
ℹ [1/3] Bundling: modules/api
✓   ✓ Bundled (4 branches, 3 tags)
...
✓ Time taken: 0m 45s
```

**Log Files**: `bundle_verification.txt` contains complete details of all operations

### 2. export_all.sh

**Purpose**: Extracts and recreates the Git repository structure from bundles on the destination network to a NEW location.

**What it does**:
- Auto-detects the import folder from `bundle_all.sh`
- Clones the super repository from the bundle
- Recreates all submodules in their original folder structure (including nested ones)
- Checks out the default branch (tries main → master → current)
- Generates documentation for future network connectivity
- Optimized with clean console output
- Shows time taken for export operation

**Output**: Creates a timestamped folder `YYYYMMDD_HHmm_export/` with the complete repository

**Console Output**:
```
ℹ [1/3] Exporting: modules/api
✓   ✓ Exported (4 branches, 3 tags)
...
✓ Time taken: 0m 30s
```

**Log Files**: `export_log.txt` contains complete details of all operations

**Use when**: Setting up a repository for the first time on a new network

### 3. sync_from_bundle.sh

**Purpose**: Updates an EXISTING repository with bundles from a newer source, treating the bundle as the source of truth.

**What it does**:
- Creates a backup of the existing repository (in git-bundles folder)
- Force resets the super repository to match the bundle
- Updates all submodules (including nested ones) to match the bundle
- Overwrites any local changes or commits not in the bundle
- Logs all operations
- Optimized with minimal console output
- Shows time taken for sync operation

**Output**: Updates the existing repository in place, creates backup in git-bundles folder

**Console Output**:
```
ℹ [1/3] Syncing: modules/api
✓   ✓ Updated
...
✓ Time taken: 0m 25s
```

**Use when**: Syncing an outdated repository with newer bundles (bundle overwrites local changes)

## Workflow Comparison

| Scenario | Use This Script |
|----------|----------------|
| First time bringing repo to new network | `export_all.sh` |
| Updating existing repo (bundle is truth) | `sync_from_bundle.sh` |
| Want to preserve local commits | Manual Git merge |
| Testing/Creating a fresh copy | `export_all.sh` |

## Usage Instructions

### Workflow 1: First Time Setup (New Network)

#### Step 1: Configure bundle_all.sh (Source Network)

Edit the `bundle_all.sh` script and configure these variables:

```bash
# Local path to the Git super repository you want to bundle
REPO_PATH="$HOME/Desktop/your-super-repository"

# SSH remote Git address (for reference/documentation purposes)
REMOTE_GIT_ADDRESS="git@bitbucket.org:your-org/your-repo.git"
```

**Windows Git Bash users**: Always use `$HOME` for portability:
```bash
REPO_PATH="$HOME/Desktop/submodule-docker-dev-workflow"
```

#### Step 2: Run bundle_all.sh (Source Network)

```bash
cd ~/Desktop/git-bundles
chmod +x bundle_all.sh
./bundle_all.sh
```

**Important Notes:**
- ✅ **Submodules do NOT need to be initialized beforehand** - The script will automatically detect submodules from `.gitmodules` files and initialize them only for bundling purposes
- ✅ **Works with or without submodules** - If your repository has no submodules, the script will simply bundle the main repository
- ✅ **Handles nested submodules** - Submodules within submodules at any depth are automatically discovered and bundled
- ✅ **Run from any directory** - The script uses the `REPO_PATH` you configured, so you can run it from anywhere

This will create a folder named like `20260126_2051_import/` containing all bundles.

#### Step 3: Verify the Bundle (Source Network)

```bash
cat 20260126_2051_import/bundle_verification.txt
```

Check that all repositories show `✓ VERIFIED` status.

#### Step 4: Transfer to Destination Network

Transfer the entire `YYYYMMDD_HHmm_import/` folder to the destination network via CD/DVD/USB.

#### Step 5: Run export_all.sh (Destination Network)

```bash
cd ~/Desktop/git-bundles
chmod +x export_all.sh
./export_all.sh
```

The script will auto-detect the import folder (or you can configure `IMPORT_FOLDER` variable).

This creates `20260126_2051_export/your-repo-name/` with the complete repository.

#### Step 6: Verify the Export

```bash
cd 20260126_2051_export/your-repo-name/
git log --oneline -10
git submodule status --recursive
```

### Workflow 2: Updating Existing Repository (Sync)

Use this when you have an **outdated repository** on the destination network and want to update it with newer bundles.

⚠️ **WARNING**: This will OVERWRITE all local changes! A backup is created automatically.

#### Step 1-4: Same as Workflow 1

Bundle on source network and transfer to destination.

#### Step 5: Configure sync_from_bundle.sh (Destination Network)

```bash
# Path to your EXISTING repository that needs updating
EXISTING_REPO_PATH="$HOME/Desktop/my-repository"

# Leave empty to auto-detect most recent import folder
IMPORT_FOLDER=""

# Default branch (tries main, then master, then current)
DEFAULT_BRANCH="main"

# Create backup before syncing (HIGHLY recommended)
CREATE_BACKUP=true
```

#### Step 6: Run sync_from_bundle.sh

```bash
cd ~/Desktop/git-bundles
chmod +x sync_from_bundle.sh
./sync_from_bundle.sh
```

**What happens:**
1. Creates backup: `git-bundles/my-repository_backup_YYYYMMDD_HHMMSS/`
2. Force resets your repository to match the bundle
3. Updates all submodules
4. Discards any local changes

#### Step 7: Verify the Sync

```bash
cd ~/Desktop/my-repository
git log --oneline -10
git submodule status --recursive
```

Your repository now matches the source network exactly!

## Folder Structure Examples

### After bundle_all.sh:
```
git-bundles/
└── 20260126_2051_import/
    ├── super-repo.bundle
    ├── submodule-a.bundle
    ├── folder_b/
    │   └── submodule-b.bundle
    ├── folder_c/
    │   └── folder_d/
    │       └── submodule-c.bundle
    │           └── nested/
    │               └── submodule-d.bundle    ← Nested!
    ├── bundle_verification.txt
    └── metadata.txt
```

### After export_all.sh:
```
git-bundles/
└── 20260126_2051_export/
    └── super-repo/
        ├── .git/
        ├── .gitmodules
        ├── submodule-a/
        ├── folder_b/
        │   └── submodule-b/
        └── folder_c/
            └── folder_d/
                └── submodule-c/
                    └── nested/
                        └── submodule-d/
```

### After sync_from_bundle.sh:
```
git-bundles/
├── 20260126_2051_import/                      ← Input bundles
├── my-repository_backup_20260126_143052/      ← Backup created
├── bundle_all.sh
├── export_all.sh
└── sync_from_bundle.sh
```

(Plus your existing repository is updated in place at its original location)

## Nested Submodules

These scripts fully support **nested submodules** (submodules within submodules) at any depth:

- The `bundle_all.sh` script recursively discovers ALL `.git` files/directories
- The `export_all.sh` and `sync_from_bundle.sh` scripts process bundles in the correct order (parent before child)
- No manual configuration needed - it just works!

**Example structure:**
```
parent-repo/
└── level1/
    └── submodule-a/           ← First level submodule
        └── nested/
            └── submodule-b/   ← Nested submodule (2nd level)
                └── deep/
                    └── submodule-c/   ← Even deeper! (3rd level)
```

## Air-Gapped Network Considerations

### Current Setup
- Repositories are cloned WITHOUT remote URLs configured
- This is intentional for security in air-gapped environments
- All git history, branches, and tags are preserved

### Future Network Connectivity
If networks eventually become connected, see `NETWORK_CONNECTIVITY_NOTES.txt` for instructions on:
- Adding remote URLs
- Configuring submodule remotes
- Pushing changes back to the source
- Syncing with remote repositories

## Verification and Safety

### bundle_all.sh Verification
The script automatically:
- Verifies each bundle using `git bundle verify`
- Calculates SHA256 checksums for integrity checking
- Records file sizes for each bundle
- Logs branch, tag, and commit counts for all repositories

### export_all.sh Verification
The script:
- Validates bundle integrity before cloning
- Ensures folder structure matches the original
- Processes bundles in correct order (parent directories before nested)
- Logs all operations for audit purposes

### sync_from_bundle.sh Safety
The script:
- Creates automatic backup before any changes (in git-bundles folder)
- Force resets to bundle state (bundle is source of truth)
- Logs all operations
- Provides clear warnings about data loss

## Troubleshooting

### Bundle verification fails
- Ensure the source repository is accessible at the configured `REPO_PATH`
- The script will automatically initialize submodules - no manual action needed
- Check that all submodules are accessible (network or file:// paths)

### Submodule not found during export/sync
- Verify the bundle exists in the correct folder in the import directory
- Check `bundle_verification.txt` for any bundles that failed verification
- Ensure the entire import folder was transferred (including subdirectories)

### Branch not found
- The scripts automatically try `main`, then `master`, then the current branch
- No manual configuration needed unless you want a specific branch
- Check the export/sync log to see which branch was checked out

### Permission denied
- Ensure scripts are executable: `chmod +x *.sh`
- Check file permissions on the import/export folders
- On Windows, run Git Bash with appropriate permissions

### Recovering from failed sync
- Backups are stored in `git-bundles/repository-name_backup_YYYYMMDD_HHMMSS/`
- Simply copy the backup back to restore: `cp -r git-bundles/backup/ ~/Desktop/my-repo/`

### Windows-Specific Issues

**Path format**: Always use `$HOME` or forward slashes:
- ✅ Good: `$HOME/Desktop/my-repo`
- ✅ Good: `/c/Users/username/Desktop/my-repo`
- ❌ Bad: `C:\Users\username\Desktop\my-repo`

**Line endings**: Scripts use Unix line endings (LF) - Git Bash handles this automatically

## Testing the Scripts

Before using these scripts on production repositories, you can test them with a comprehensive test repository that includes all edge cases.

### Included Test Scripts

The repository includes two test scripts:

1. **create_full_test_repo.sh** - Creates a comprehensive test repository with:
   - Super repository with 4 branches, 4 tags
   - 2 root-level submodules (each with 4 branches, 3 tags)
   - 2 nested submodules at level 2 (each with 3 branches, 2 tags)
   - 1 deeply nested submodule at level 3 (3 branches, 2 tags)
   - **TOTAL: 21 branches, 16 tags across 6 repositories**

2. **verify_full_test.sh** - Automatically verifies that all branches, tags, and commits were transferred correctly

### Test Repository Structure

The test creates this structure (in `git-bundles/test/`):

```
full-test-repo/                                    ← Super Repository
├── 4 branches: main, develop, feature/api-gateway, release/2.0
├── 4 tags: v1.0.0, v1.5.0, v2.0.0-dev, v2.0.0
│
└── services/
    ├── user-service/                              ← ROOT-LEVEL Submodule
    │   ├── 4 branches: main, develop, feature/oauth, release/2.0
    │   ├── 3 tags: v1.0.0, v1.5.0, v2.0.0
    │   │
    │   └── lib/
    │       └── database/                          ← NESTED Level 2
    │           ├── 3 branches: main, develop, feature/pool
    │           ├── 2 tags: v1.0, v2.0
    │           │
    │           └── utils/
    │               └── logger/                    ← DEEPLY NESTED Level 3
    │                   ├── 3 branches: main, develop, feature/json
    │                   └── 2 tags: v1.0, v2.0
    │
    └── payment-service/                           ← ROOT-LEVEL Submodule
        ├── 4 branches: main, develop, feature/stripe, hotfix/1.0.1
        ├── 3 tags: v1.0.0, v1.2.0, v1.0.1
        │
        └── lib/
            └── cache/                             ← NESTED Level 2
                ├── 3 branches: main, develop, feature/redis
                └── 2 tags: v1.0, v1.5
```

### Complete Testing Procedure

#### Step 1: Create the Test Repository

```bash
cd ~/Desktop/git-bundles
chmod +x create_full_test_repo.sh
./create_full_test_repo.sh
```

This creates the test repository at: `~/Desktop/git-bundles/test/full-test-repo/`

#### Step 2: Configure bundle_all.sh

Edit `bundle_all.sh` and set:

```bash
REPO_PATH="$HOME/Desktop/git-bundles/test/full-test-repo"
REMOTE_GIT_ADDRESS="git@example.com:test/full-test-repo.git"
```

Or on Windows Git Bash, the script will show you the exact path to use.

#### Step 3: Run Bundle

```bash
./bundle_all.sh
```

**Expected output:**
```
ℹ [1/5] Bundling: services/user-service
✓   ✓ Bundled (4 branches, 3 tags)
ℹ [2/5] Bundling: services/payment-service
✓   ✓ Bundled (4 branches, 3 tags)
ℹ [3/5] Bundling: services/user-service/lib/database
✓   ✓ Bundled (3 branches, 2 tags)
ℹ [4/5] Bundling: services/payment-service/lib/cache
✓   ✓ Bundled (3 branches, 2 tags)
ℹ [5/5] Bundling: services/user-service/lib/database/utils/logger
✓   ✓ Bundled (3 branches, 2 tags)
...
✓ Time taken: 0m XX s
```

#### Step 4: Run Export

```bash
./export_all.sh
```

**Expected output:**
```
ℹ [1/5] Exporting: services/user-service
✓   ✓ Exported (4 branches, 3 tags)
ℹ [2/5] Exporting: services/payment-service
✓   ✓ Exported (4 branches, 3 tags)
...
✓ Time taken: 0m XX s
```

#### Step 5: Run Automated Verification

```bash
chmod +x verify_full_test.sh
./verify_full_test.sh
```

**Expected output if all tests pass:**
```
✓ ALL CHECKS PASSED!

✓ All 21 branches transferred correctly
✓ All 16 tags transferred correctly
✓ All repositories are air-gapped (no remotes)
✓ Root-level submodules have all branches (not just main)
✓ Nested submodules have all branches

✓ Bundle and export scripts are working perfectly!
```

#### Step 6: Manual Verification (Optional)

If you want to check manually:

```bash
cd YYYYMMDD_HHmm_export/full-test-repo

# Quick summary
echo "Super repo: $(git branch | wc -l) branches (expected: 4)"
echo "user-service: $(cd services/user-service && git branch | wc -l) branches (expected: 4)"
echo "payment-service: $(cd services/payment-service && git branch | wc -l) branches (expected: 4)"
echo "database-lib: $(cd services/user-service/lib/database && git branch | wc -l) branches (expected: 3)"
echo "cache-lib: $(cd services/payment-service/lib/cache && git branch | wc -l) branches (expected: 3)"
echo "logger-lib: $(cd services/user-service/lib/database/utils/logger && git branch | wc -l) branches (expected: 3)"
```

### What This Test Validates

This comprehensive test ensures:

- ✅ **Root-level submodules** get ALL branches (not just main)
- ✅ **Nested submodules** at level 2 get all branches
- ✅ **Deeply nested** submodules at level 3 get all branches
- ✅ **Super repository** gets all branches
- ✅ **All tags** are transferred correctly
- ✅ **No remote tracking** branches (pure local)
- ✅ **Air-gapped setup** works correctly
- ✅ **Recursive discovery** finds all submodules
- ✅ **Bundle verification** passes for all repositories
- ✅ **Export process** recreates structure correctly

### Cleaning Up Test Files

After testing, you can remove the test repository:

```bash
cd ~/Desktop/git-bundles
rm -rf test/
rm -rf YYYYMMDD_HHmm_import/
rm -rf YYYYMMDD_HHmm_export/
```

## Advanced Usage

### Testing with Nested Submodules

Use the included `create_full_test_repo.sh` script as described in the **Testing the Scripts** section above.

### Custom timestamp folders
The scripts use `YYYYMMDD_HHmm` format. Multiple exports on the same day will have different timestamps (down to the minute).

### Import folder auto-detection
When `IMPORT_FOLDER=""` is left empty, scripts find the most recent `*_import` folder by sorting folder names (which are chronologically ordered due to the timestamp format).

## Security Notes

- Always verify SHA256 checksums match between source and destination
- Review `bundle_verification.txt` before transferring
- Keep audit logs of all transfers between networks
- Follow your organization's air-gap transfer procedures
- For local test repositories, the scripts enable `file://` protocol automatically
- When using `sync_from_bundle.sh`, ensure bundles are from a trusted source

## Platform Support

- ✅ **Linux** - Native bash support
- ✅ **Windows** - Git Bash (MINGW64)
- ✅ **WSL** - Windows Subsystem for Linux

## Support

For issues or questions:
1. Check the verification logs (`bundle_verification.txt`, `export_log.txt`)
2. Review `NETWORK_CONNECTIVITY_NOTES.txt` for remote setup
3. Review `SYNC_WORKFLOW.md` for detailed sync instructions
4. Ensure Git version compatibility between networks (Git 2.x recommended)

## Additional Documentation

- `SYNC_WORKFLOW.md` - Detailed guide for syncing/updating existing repositories
- `create_full_test_repo.sh` - Creates comprehensive test repository with 21 branches, 16 tags
- `verify_full_test.sh` - Automated verification script for test results

## Quick Reference

```bash
# Test the scripts (recommended before production use)
cd ~/Desktop/git-bundles
./create_full_test_repo.sh  # Creates test repo
# Edit bundle_all.sh to set REPO_PATH to test/full-test-repo
./bundle_all.sh             # Bundle test repo
./export_all.sh             # Export test repo
./verify_full_test.sh       # Verify all branches transferred

# Bundle a repository (source network)
cd ~/Desktop/git-bundles
./bundle_all.sh

# Export to new location (destination network - first time)
./export_all.sh

# Sync existing repository (destination network - updates)
./sync_from_bundle.sh
```

---

**Last Updated**: January 28, 2026  
**Tested With**: Git 2.x on Windows Git Bash and Linux  