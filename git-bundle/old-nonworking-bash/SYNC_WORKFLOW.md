# Syncing/Updating Existing Repositories

This guide explains how to update an existing repository on an air-gapped network with newer bundles from another network.

## Scenario

You have:
- **Source Network** (Network A): The most up-to-date repository
- **Destination Network** (Network B): An older version of the same repository

You want to:
- Bring the bundles from Network A to Network B
- **Overwrite** Network B's repository with Network A's version (treating Network A as source of truth)

## Important Warning

⚠️ **The `sync_from_bundle.sh` script will OVERWRITE all local changes!**

- Any uncommitted changes will be **LOST**
- Any commits not in the bundle will be **LOST**  
- The bundle is treated as the **authoritative source of truth**
- A backup is created by default (can be disabled)

## Workflow

### Network A (Source - Most Up to Date)

1. **Bundle the repository:**
   ```bash
   cd ~/Desktop/git-bundles
   # Edit bundle_all.sh: REPO_PATH="$HOME/Desktop/my-repository"
   ./bundle_all.sh
   ```

2. **Transfer the import folder:**
   - Copy the entire `YYYYMMDD_HHmm_import/` folder to physical media
   - Transfer to Network B

### Network B (Destination - Out of Date)

3. **Place the import folder:**
   ```bash
   # Copy the import folder to your working directory
   cp -r /media/cd/20260126_2145_import ~/Desktop/git-bundles/
   cd ~/Desktop/git-bundles
   ```

4. **Configure sync script:**
   ```bash
   # Edit sync_from_bundle.sh
   EXISTING_REPO_PATH="$HOME/Desktop/my-repository"  # Path to your EXISTING repo
   IMPORT_FOLDER=""  # Leave empty for auto-detect
   DEFAULT_BRANCH="main"
   CREATE_BACKUP=true  # Highly recommended!
   ```

5. **Run the sync:**
   ```bash
   chmod +x sync_from_bundle.sh
   ./sync_from_bundle.sh
   ```

## What the Sync Script Does

### Step-by-Step Process:

1. **Validates Paths**
   - Checks that the existing repository exists
   - Locates the import folder with bundles (auto-detects by timestamp in folder name)

2. **Creates Backup** (if enabled)
   - Makes a complete copy of your existing repository
   - Saves it in the **git-bundles folder** (same location as import/export folders)
   - Names it: `repository-name_backup_YYYYMMDD_HHMMSS`
   - Example: `~/Desktop/git-bundles/myapp_backup_20260126_143052`

3. **Syncs Super Repository**
   - Fetches all branches and tags from the bundle
   - **Force resets** to the bundle's state (`git reset --hard`)
   - Discards any local changes or commits not in the bundle

4. **Syncs All Submodules**
   - Processes each submodule (including nested ones)
   - For existing submodules: Force resets to bundle state
   - For new submodules: Clones from bundle
   - Maintains correct folder structure

5. **Reports Results**
   - Shows what was synced
   - Reminds you about the backup location

## File Locations

All files related to the git bundle workflow are stored in the **git-bundles** directory:

```
~/Desktop/git-bundles/
├── 20260126_1430_import/              ← Bundles from source network
├── 20260126_1430_export/              ← Fresh export (if using export_all.sh)
├── myapp_backup_20260126_143052/      ← Backup before sync
├── bundle_all.sh
├── export_all.sh
└── sync_from_bundle.sh
```

**Your actual repository** being synced stays in its original location (e.g., `~/Desktop/my-repository`).

## Configuration Options

### EXISTING_REPO_PATH
```bash
EXISTING_REPO_PATH="$HOME/Desktop/my-repository"
```
**Required**. Path to the repository you want to update.

### IMPORT_FOLDER
```bash
IMPORT_FOLDER=""  # Auto-detect (finds most recent by timestamp in folder name)
# OR
IMPORT_FOLDER="20260126_2145_import"  # Specific folder
```
**Optional**. Leave empty to auto-detect the most recent `*_import` folder. Auto-detection works by sorting folder names (which are chronologically ordered because of the `YYYYMMDD_HHmm` timestamp format).

### DEFAULT_BRANCH
```bash
DEFAULT_BRANCH="main"  # or "master", "develop", etc.
```
**Optional**. The script will try this branch first, then fall back to `master`, then any available branch.

### CREATE_BACKUP
```bash
CREATE_BACKUP=true   # Create backup (recommended)
CREATE_BACKUP=false  # Skip backup (faster, but risky)
```
**Optional**. Highly recommended to keep enabled!

## Example: Full Sync Workflow

### Scenario: Updating Production from Development

**Development Network (Source of Truth):**
```bash
cd ~/Desktop/git-bundles

# Configure bundle_all.sh
# REPO_PATH="$HOME/projects/myapp"
./bundle_all.sh

# Output: 20260126_1430_import/
```

**Transfer via physical media to Production Network**

**Production Network (Out of Date):**
```bash
# Copy import folder from CD/DVD
cp -r /media/cd/20260126_1430_import ~/Desktop/git-bundles/
cd ~/Desktop/git-bundles

# Configure sync_from_bundle.sh
# EXISTING_REPO_PATH="$HOME/production/myapp"
./sync_from_bundle.sh
```

**Result:**
- Production repository now matches Development exactly
- All submodules synced
- Backup saved in case you need to revert

## Verification After Sync

```bash
cd $HOME/Desktop/my-repository

# Check the repository state
git log --oneline -10
git status

# Check submodules
git submodule status --recursive

# Verify no uncommitted changes
git diff

# Check current branch
git branch
```

## Recovering from Backup

If something goes wrong and you need to restore:

```bash
# The backup is in your git-bundles folder
cd ~/Desktop/git-bundles
ls -la *_backup_*

# Remove the synced repository
rm -rf ~/Desktop/my-repository

# Restore from backup
cp -r ~/Desktop/git-bundles/my-repository_backup_20260126_143052 ~/Desktop/my-repository
```

**Note:** Backups are stored in the `git-bundles` folder alongside your import/export folders for easy organization.

## Comparison: export_all.sh vs sync_from_bundle.sh

### export_all.sh (Create New Repository)
- ✅ Creates repository in a **new** location
- ✅ Safe - doesn't touch existing repositories
- ✅ Good for first-time setup
- ❌ Can't update existing repositories

### sync_from_bundle.sh (Update Existing Repository)
- ✅ Updates repository **in place**
- ✅ Handles conflicts by treating bundle as source of truth
- ✅ Good for ongoing synchronization
- ⚠️ **OVERWRITES local changes** (by design)

## Best Practices

1. **Always create backups** (leave `CREATE_BACKUP=true`)

2. **Verify before syncing:**
   ```bash
   cd $EXISTING_REPO_PATH
   git status
   git log --oneline -5
   ```

3. **Test on a copy first** if unsure:
   ```bash
   cp -r ~/production/myapp ~/test/myapp
   # Then sync the test copy
   ```

4. **Document your syncs:**
   - Keep a log of when you synced
   - Note which import folder you used
   - Record the backup location

5. **Clean up old backups** periodically:
   ```bash
   # Backups are in git-bundles folder
   cd ~/Desktop/git-bundles
   ls -ld *_backup_*
   
   # Remove old backups (be careful!)
   rm -rf my-repository_backup_20260115_*
   ```

## Troubleshooting

### "Repository path does not exist"
- Check that `EXISTING_REPO_PATH` is correct
- Use `$HOME` for portability: `$HOME/Desktop/my-repo`

### "No *_import folder found"
- Ensure the import folder is in the same directory as the script
- Or set `IMPORT_FOLDER` explicitly

### "Not a Git repository"
- The path exists but isn't a Git repo
- Check that there's a `.git` directory: `ls -la $EXISTING_REPO_PATH/.git`

### Sync failed partway through
- Check if backup exists: `ls -ld *_backup_*`
- Restore from backup if needed
- Review error messages for specific issues

### Want to preserve some local commits
- **Don't use this script** - it will overwrite them
- Instead, manually merge using standard Git commands:
  ```bash
  git fetch bundle_file.bundle 'refs/heads/*:refs/remotes/bundle/*'
  git merge bundle/main
  # Resolve conflicts manually
  ```

## Security Considerations

- ✅ Backup created by default
- ✅ Script requires explicit configuration (no accidents)
- ✅ All changes logged to terminal
- ⚠️ Destructive by design (overwrites local changes)
- ⚠️ Review bundles before syncing to ensure they're from trusted source

## When to Use Each Script

| Scenario | Use This Script |
|----------|----------------|
| First time bringing repo to new network | `export_all.sh` |
| Updating existing repo (bundle is truth) | `sync_from_bundle.sh` |
| Want to preserve local commits | Manual Git merge |
| Testing/Development | `export_all.sh` (to new location) |
| Production sync with no local changes | `sync_from_bundle.sh` |

---

**Remember:** `sync_from_bundle.sh` treats the bundle as the authoritative source of truth. Any local changes or commits not in the bundle will be permanently lost (unless you have a backup).